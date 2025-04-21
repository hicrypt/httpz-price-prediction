// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IVault {
    function owner() external view returns (address);

    event PredictionCreated(address indexed token, address indexed prediction);
    error PredictionExists();
}
