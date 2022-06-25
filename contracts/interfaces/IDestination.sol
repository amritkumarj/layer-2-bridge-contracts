// SPDX-License-Identifier: GPL-3.0

import "../utils/DataType.sol";

pragma solidity 0.8.7;

interface IDestination{

    event NewTransfer(
        DataType.TransferData transferData
    );
    function claim(DataType.TransferData memory transferData) external payable;

    function getLPFee(uint256 startTime, uint256 fee, uint256 feeRampup) external view returns(uint256);

    function declareNewHashChainHead() external;

}