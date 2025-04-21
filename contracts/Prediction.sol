// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPrediction} from "./interfaces/IPrediction.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract Prediction is Ownable2Step, SepoliaZamaFHEVMConfig, GatewayCaller, Pausable, IPrediction {
    using SafeERC20 for IERC20;
    using TFHE for ebool;
    using TFHE for euint256;

    struct Round {
        uint256 lockPrice;
        uint256 closePrice;
        uint256 startTime;
        uint256 lockTime;
        uint256 closeTime;
        uint256 totalAmount;
        euint256 bullAmount;
        bool isGenesis;
    }

    struct RoundUserInfo {
        ebool betBull;
        euint256 amount;
        bool claimed;
    }

    struct DecryptRequest {
        uint64 roundId;
        address user;
    }

    uint256 constant MIN_ROUND_INTERVAL = 1 minutes;
    IERC20 immutable public override TOKEN;
    address public immutable VAULT;

    IPriceOracle public priceOracle;
    uint256 public minBetAmount;
    uint256 public roundInterval;
    uint256 public bufferInterval;

    uint64 public currentRoundId;  // Current round to bet
    mapping(uint64 roundId => Round) public rounds;

    mapping(uint64 roundId => mapping(address user => RoundUserInfo)) public userInfo;

    mapping(uint256 requestId => DecryptRequest) public decryptRequests;

    constructor(address token) Ownable(IVault(msg.sender).owner()) {
        if (token == address(0)) revert ZeroAddress();
        TOKEN = IERC20(token);
        VAULT = msg.sender;

        _pause();
    }

    function bet(uint256 amount, ebool bull) external override {
        _requireValidConfig();

        if (amount < minBetAmount) revert InvalidBetAmount();

        uint64 _currentRoundId = currentRoundId;

        Round memory _currentRound = rounds[_currentRoundId];
        if (block.timestamp >= _currentRound.lockTime) revert RoundAlreadyLocked();
        if (_currentRound.isGenesis) revert IsGenesisRound();

        RoundUserInfo storage _userInfo = userInfo[_currentRoundId][msg.sender];
        
        if (_userInfo.betBull.isInitialized()) revert AlreadyBet();

        TOKEN.safeTransferFrom(msg.sender, VAULT, amount);

        euint256 _amount = TFHE.asEuint256(amount);

        _currentRound.totalAmount = _currentRound.totalAmount + amount;
        _currentRound.bullAmount = _currentRound.bullAmount.add(TFHE.select(bull, _amount, TFHE.asEuint256(0)));

        rounds[_currentRoundId] = _currentRound;

        _userInfo.amount = _amount;
        _userInfo.betBull = bull;

        emit Betted(msg.sender, _currentRoundId, amount);
    }

    function claim(uint64 roundId) external {
        if (_claim(roundId) == false) revert UnableToClaim(msg.sender, roundId);
    }

    function claimInBatch(uint64[] memory roundIds) external {
        uint256 len = roundIds.length;
        for (uint256 i; i < len; i += 1) {
            _claim(roundIds[roundIds[i]]);
        }
    }

    function executeNextRound() external {
        _requireValidConfig();

        uint64 _currentRoundId = currentRoundId;

        Round memory _currentRound = rounds[_currentRoundId];

        if (_currentRound.lockTime != 0 && block.timestamp < _currentRound.lockTime) revert RoundNotReadyToLock();

        uint256 _price = getCurrentPrice();

        if (_currentRound.isGenesis == false) {
            uint64 _prevRoundId = _currentRoundId - 1;
            rounds[_prevRoundId].closePrice = _price;
            rounds[_prevRoundId].bullAmount.allowThis();

            emit RoundClosed(_prevRoundId, _price);
        }

        rounds[_currentRoundId].lockPrice = _price;
        emit RoundLocked(_currentRoundId, _price);

        _startNewRound(false);
    }

    function getCurrentPrice() public override view returns (uint256 price) {
        price = priceOracle.getCurrentPrice(address(TOKEN));
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        _requirePaused();

        // Query price once to valid oracle
        IPriceOracle(_priceOracle).getCurrentPrice(address(TOKEN));

        priceOracle = IPriceOracle(_priceOracle);

        emit PriceOracleSet(_priceOracle);
    }

    function setMinBetAmount(uint256 _minBetAmount) external onlyOwner {
        _requirePaused();

        if (_minBetAmount == 0) revert ZeroAmount();

        minBetAmount = _minBetAmount;
    }

    function setRoundInterval(uint256 _roundInterval) external onlyOwner {
        _requirePaused();

        if (_roundInterval < MIN_ROUND_INTERVAL) revert InvalidRoundInterval();

        roundInterval = _roundInterval;
    }

    function unpause() external onlyOwner {
        _requirePaused();
        if (address(priceOracle) == address(0)) revert NoPriceOracle();
        if (minBetAmount == 0) revert NoMinBetAmount();
        if (roundInterval == 0) revert NoRoundInterval();
        if (bufferInterval == 0) revert NoBufferInterval();

        _unpause();
        _startNewRound(true);
    }

    function pause() external onlyOwner {
        _requireNotPaused();

        _pause();
    }
    
    function _startNewRound(bool isGenesis) internal {
        uint64 _nextRoundId = currentRoundId + 1;

        Round storage _nextRound = rounds[_nextRoundId];
        _nextRound.startTime = block.timestamp;
        _nextRound.lockTime = block.timestamp + roundInterval;
        _nextRound.closeTime = block.timestamp + roundInterval * 2;
        _nextRound.isGenesis = isGenesis;

        currentRoundId = _nextRoundId;

        emit RoundStarted(_nextRoundId, isGenesis);
    }
    
    function _claim(uint64 roundId) public returns (bool success) {
        Round memory _roundInfo = rounds[roundId];
        RoundUserInfo memory _userInfo = userInfo[roundId][msg.sender];
        if (_userInfo.claimed) success = false;
        else if ((_roundInfo.lockPrice == 0 || _roundInfo.closePrice == 0) && block.timestamp < _roundInfo.closeTime + bufferInterval) {
            success = false;
        } else {
            _requestDecryption(roundId, msg.sender);
        }
    }

    function _requestDecryption(uint64 roundId, address user) internal {
        Round memory _roundInfo = rounds[roundId];
        RoundUserInfo memory _userInfo = userInfo[roundId][user];

        _userInfo.amount.allowThis();
        _userInfo.betBull.allowThis();

        uint256[] memory cts = new uint256[](3);
        cts[0] = Gateway.toUint256(_roundInfo.bullAmount);
        cts[0] = Gateway.toUint256(_userInfo.amount);
        cts[0] = Gateway.toUint256(_userInfo.betBull);

        uint256 requestId = Gateway.requestDecryption(cts, this.callbackDecryptedValues.selector, 0, block.timestamp + 100, false);

        decryptRequests[requestId] = DecryptRequest({
            roundId: roundId,
            user: user
        });
    }

    function callbackDecryptedValues(uint256 requestId, uint256 bullAmount, uint256 betAmount, bool betBull) external onlyGateway {
        DecryptRequest memory request = decryptRequests[requestId];

        if (request.user == address(0)) revert DecryptionError();

        Round memory _roundInfo = rounds[request.roundId];
        RoundUserInfo memory _userInfo = userInfo[request.roundId][request.user];

        if (_userInfo.claimed == false) {
            uint256 claimAmount;
            if ((_roundInfo.lockPrice == 0 || _roundInfo.closePrice == 0) && block.timestamp >= _roundInfo.closeTime + bufferInterval) {
                // Refund after buffer intervals
                claimAmount = betAmount;
            }
            if (_roundInfo.lockPrice < _roundInfo.closePrice && betBull) {
                claimAmount = _roundInfo.totalAmount * betAmount / bullAmount;
            } else if (_roundInfo.lockPrice > _roundInfo.closePrice && betBull == false) {
                claimAmount = _roundInfo.totalAmount * betAmount / (_roundInfo.totalAmount - bullAmount);
            } else if (_roundInfo.lockPrice == _roundInfo.closePrice) {
                claimAmount = betAmount;
            }

            if (claimAmount != 0) {
                IVault(VAULT).withdrawTokenToUser(address(TOKEN), request.user, claimAmount);
            }

            // Set claimed to true even claimAmount is 0 to avoid re-decryption.
            userInfo[request.roundId][request.user].claimed = true;
        } else {
            // Do not revert to delete multiple requests for same round id and user
        }

        delete decryptRequests[requestId];
    }

    function _requireValidConfig() internal view {
        _requireNotPaused();
        if (address(priceOracle) == address(0)) revert NoPriceOracle();
        if (minBetAmount == 0) revert NoMinBetAmount();
        if (roundInterval == 0) revert NoRoundInterval();
        if (bufferInterval == 0) revert NoBufferInterval();
    }    
}
