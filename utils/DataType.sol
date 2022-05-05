//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

library DataType {
    struct TransferData{
        address tokenAddress;
        address destination;
        address sender;
        uint256 amount;
        uint256 fee;
        uint256 startTime;
        uint256 feeRampup;
        uint256 nonce;

    }
    struct RewardData{
        bytes32 transferHash;
        address tokenAddress;
        address claimer;
        uint256 amount;
    }
}