// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "fhevm/lib/TFHE.sol";

interface IPrediction {
    function TOKEN() external view returns (IERC20 token);

    function VAULT() external view returns (address vault);

    function bet(uint256 amount, ebool bull) external;

    function getCurrentPrice() external view returns (uint256 price);

    event Betted(address indexed user, uint64 indexed roundId, uint256 amount);
    event RoundLocked(uint64 indexed roundId, uint256 lockPrice);
    event RoundClosed(uint64 indexed roundId, uint256 lockPrice);
    event RoundStarted(uint64 indexed roundId, bool isGenesis);

    event PriceOracleSet(address indexed priceFeed);

    error ZeroAddress();
    error AlreadyBet();
    error NoPriceOracle();
    error NoMinBetAmount();
    error NoRoundInterval();
    error NoBufferInterval();

    error InvalidBetAmount();
    error RoundNotReadyToLock();
    error RoundAlreadyLocked();
    error AlreadySet();
    error IsGenesisRound();
    error ZeroAmount();
    error InvalidRoundInterval();
    error UnableToClaim(address user, uint64 roundId);
}
