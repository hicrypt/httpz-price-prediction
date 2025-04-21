// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IVault {
    function owner() external view returns (address);

    function withdrawTokenToUser(address token, address user, uint256 amount) external;

    event PredictionCreated(address indexed token, address indexed prediction);
    error PredictionExists();
    error Unauthorized();
}
