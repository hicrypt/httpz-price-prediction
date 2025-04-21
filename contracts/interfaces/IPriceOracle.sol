// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IPriceOracle {
    function getCurrentPrice(address token) external view returns (uint256 price);
}
