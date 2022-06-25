// SPDX-License-Identifier: GPL-3.0

import "../utils/DataType.sol";

pragma solidity 0.8.7;

interface ISource{
    event NewTransfer(
        DataType.TransferData transferData
    );
    function transfer(address tokenAddress, address destination, uint256 amount, uint256 feeRampup) external payable;
    function processClaims(DataType.RewardData[] memory rewardDataList) external;
    function refundFunction(DataType.TransferData memory transferData) external;
    function declareNewHashChainHead(bytes32[] memory newOnionHashes) external;
    function getLPFees(uint256 amount) external view returns(uint256 fee,uint256 amountPlusFee);
}