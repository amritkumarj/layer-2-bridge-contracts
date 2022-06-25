// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

interface IBonding{
    function passData(bytes32[] memory rewardHashList) external;
}