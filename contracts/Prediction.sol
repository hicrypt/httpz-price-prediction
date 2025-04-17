// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";

contract Prediction is Ownable2Step, SepoliaZamaFHEVMConfig {
    using SafeERC20 for IERC20;
    using TFHE for ebool;
    using TFHE for euint256;

    event Betted(address indexed user, address indexed token, uint256 indexed roundId, uint256 amount);
    event RoundClosed(address indexed token, uint256 roundId, uint256 closedPrice);

    struct Round {
        uint256 lockPrice;
        uint256 closedPrice;
        uint256 startTime;
        uint256 closeTime;
        euint256 totalAmount;
        euint256 bullAmount;
        mapping(address user => ebool) betBull;
        mapping(address user => euint256) amounts;
    }

    struct PoolInfo {
        address priceFeed;
        uint256 minBetAmount;
        bool isActive;
    }

    address constant NATIVE_TOKEN = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 constant ROUND_TIME = 5 minutes;

    mapping(address token => PoolInfo) public poolInfo;
    mapping(address token => uint256) public currentRoundId;
    mapping(address token => Round[]) public rounds;

    constructor() Ownable(msg.sender) {}

    function bet(address token, uint256 amount, ebool bull) external {
        address _token = token;
        _onlyValidPool(_token);
        if (poolInfo[_token].minBetAmount > amount || amount == 0) revert InvalidBetAmount();

        uint256 _currentRoundId = currentRoundId[_token];

        Round storage currentRound = rounds[_token][_currentRoundId];
        
        if (currentRound.betBull[msg.sender].isInitialized()) revert AlreadyBet();

        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);

        euint256 _amount = TFHE.asEuint256(amount);

        currentRound.totalAmount = currentRound.totalAmount.add(_amount);
        currentRound.bullAmount = currentRound.bullAmount.add(TFHE.select(bull, _amount, TFHE.asEuint256(0)));
        currentRound.amounts[msg.sender] = _amount;
        currentRound.betBull[msg.sender] = bull;

        _amount.allow(msg.sender);

        emit Betted(msg.sender, _token, _currentRoundId, amount);
    }

    function nextRound(address token) external {
        address _token = token;
        _onlyValidPool(_token);

        uint256 _currentRoundId = currentRoundId[_token];
        Round storage currentRound = rounds[_token][_currentRoundId];

        if (block.timestamp < currentRound.startTime + ROUND_TIME) revert NotReadyToClose();
        if (currentRound.closedPrice != 0) revert AlreadyClosed();

        uint256 _price = getCurrentPrice(_token);
        currentRound.closedPrice = _price;
        currentRound.closeTime = block.timestamp;

        emit RoundClosed(_token, currentRoundId[_token] ++, _price);
    }

    function getCurrentPrice(address token) public view returns (uint256 price) {
        address priceFeed = poolInfo[token].priceFeed;

        // TODO: check price
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(priceFeed).latestRoundData();

        if (answer < 0) revert InvalidPrice();

        price = uint256(answer);
    }

    function setPoolPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();

        poolInfo[token].priceFeed = priceFeed;

        emit PriceFeedSet(token, priceFeed);
    }

    function setPoolMinBetAmount(address token, uint256 minBetAmount) external onlyOwner {
        poolInfo[token].minBetAmount = minBetAmount;
    }

    function setPoolActive(address token, bool isActive) external onlyOwner {
        poolInfo[token].isActive = isActive;
    }

    function _onlyValidPool(address token) internal view {
        PoolInfo memory pool = poolInfo[token];
        if (pool.priceFeed == address(0)) revert PoolNoOracle();
        if (pool.isActive == false) revert PoolNotActive();
    }

    error ZeroAddress();
    error AlreadyBet();
    error PoolNoOracle();
    error PoolNotActive();
    error InvalidBetAmount();
    error InvalidPrice();
    error AlreadyClosed();
    error NotReadyToClose();

    event PriceFeedSet(address indexed token, address indexed priceFeed);
}
