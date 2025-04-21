// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPrediction, Prediction} from "./Prediction.sol";
import {IVault} from "./interfaces/IVault.sol";

contract Vault is Ownable2Step, IVault {
    using SafeERC20 for IERC20;

    address constant NATIVE_TOKEN = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 constant MIN_ROUND_TIME = 1 minutes;

    mapping(address token => IPrediction) public predictions;

    constructor() Ownable(msg.sender) {}

    function newPrediction(address token) external {
        address _token = token;

        if (address(predictions[_token]) != address(0)) revert PredictionExists();

        Prediction _prediction = new Prediction{salt: keccak256(abi.encode(_token))}(_token);

        predictions[_token] = _prediction;

        emit PredictionCreated(_token, address(_prediction));
    }

    function withdrawTokenToUser(address token, address user, uint256 amount) external override {
        if (msg.sender != address(predictions[token])) revert Unauthorized();

        IERC20(token).safeTransfer(user, amount);
    }

    function owner() public view override(Ownable, IVault) returns (address) {
        return super.owner();
    }
}
