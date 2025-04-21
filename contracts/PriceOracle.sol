// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract PriceOracle is Ownable2Step, IPriceOracle {
    mapping(address token => AggregatorV3Interface) public priceFeeds;

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address token, address priceFeed) external {
        priceFeeds[token] = AggregatorV3Interface(priceFeed);
    }

    function getCurrentPrice(address token) external view returns (uint256 price) {
        AggregatorV3Interface priceFeed = priceFeeds[token];
        
        // TODO: check stale price later;
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        
        price = uint256(answer);
    }
}
