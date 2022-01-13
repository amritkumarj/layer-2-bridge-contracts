// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISource{
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

    event newTransfer(
        TransferData transferData
    );
    function transfer(TransferData memory transferData) external payable;

    function declareNewHashChainHead(bytes32[] memory newOnionHashes) external;
    function processClaims(RewardData[] memory rewardDataList) external;
    function refundFunction(TransferData memory transferData) external;
}
contract Source is ISource{
    uint8 CONTRACT_FEE_BASIS_POINTS = 5;
    using SafeERC20 for IERC20;
    uint8 public constant NEW_TRANSACTION = 0;
    uint8 public constant PENDING_TRANSACTION = 1;
    uint8 public constant COMPLETED_TRANSACTION = 2;

    uint8 public constant MINIMUM_REFUND_DAYS = 8;

    mapping(bytes32 => uint8) validTransferHashes;
    mapping(bytes32 => bool) knownHashOnions;

    bytes32 processedRewardHashOnion;
    address constant ETH_ADDRESS = address(0);
    uint256 processedTransferCount;
    address owner;
    address L1ContractAddress;

    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);
    
    function undoL1ToL2Alias(address l2Address) internal pure returns (address l1Address) {
        l1Address = address(uint160(l2Address) - offset);
    }

    modifier fromL1Contract(){
        require(undoL1ToL2Alias(msg.sender) == L1ContractAddress, "Not Allowed");
        _;
    }

   
    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }
    constructor(address L1Address){
        processedTransferCount = 0;
        processedRewardHashOnion = 0;
        owner = msg.sender;
        L1ContractAddress = L1Address;
    }

     function updateL1Address(address L1Address) public onlyOwner{
        L1ContractAddress = L1Address;
    }
    function transfer(TransferData memory transferData) external payable override {
        uint256 amountPlusFee = (transferData.amount * (10000 + CONTRACT_FEE_BASIS_POINTS)) / 10000; 
        require(amountPlusFee >= 0.001 ether);
        transferData.startTime = block.timestamp;
        transferData.sender = msg.sender;
        bytes32 transferHash = keccak256(abi.encode(transferData));

        if(validTransferHashes[transferHash] != NEW_TRANSACTION){
            transferData.nonce += 1;
            transferHash = keccak256(abi.encode(transferData));
        }

        require(validTransferHashes[transferHash] == NEW_TRANSACTION);
        if(transferData.tokenAddress == ETH_ADDRESS){
            require(msg.value + tx.gasprice == amountPlusFee);
            emit newTransfer(transferData);
            validTransferHashes[transferHash] = PENDING_TRANSACTION;
            return;
            
        }else{
            IERC20(transferData.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amountPlusFee
            );
            emit newTransfer(transferData);
            validTransferHashes[transferHash] = PENDING_TRANSACTION;
            return;
        }
    }
  

    function declareNewHashChainHead(bytes32[] memory newOnionHashes) external override fromL1Contract{
        for (uint256 i = 0; i < newOnionHashes.length; i++) {
            bytes32 newOnionHash = newOnionHashes[i];
            if(!knownHashOnions[newOnionHash]){
                knownHashOnions[newOnionHash] = true;
            }
        }
    }

    function processClaims(RewardData[] memory rewardDataList) external override{
        bytes32 tempProcessedRewardHashOnion = processedRewardHashOnion;
        for (uint256 i = 0; i < rewardDataList.length; i++) {
            RewardData memory rewardData = rewardDataList[i];
            tempProcessedRewardHashOnion = keccak256(abi.encode(tempProcessedRewardHashOnion,keccak256(abi.encode(rewardData))));
        }

        require(knownHashOnions[tempProcessedRewardHashOnion],"Unknown Hash");

        processedRewardHashOnion = tempProcessedRewardHashOnion;

        for (uint256 i = 0; i < rewardDataList.length; i++) {

            RewardData memory rewardData = rewardDataList[i];
            if(validTransferHashes[rewardData.transferHash] == PENDING_TRANSACTION){

                validTransferHashes[rewardData.transferHash] = COMPLETED_TRANSACTION;


                if(rewardData.tokenAddress == ETH_ADDRESS){
                    
                    payable(rewardData.claimer).transfer(rewardData.amount);
            
                }else{
                    IERC20(rewardData.tokenAddress).safeTransfer(
                        rewardData.claimer,
                        rewardData.amount
                    );
                }
            }
        }
    }

    function refundFunction(TransferData memory transferData) external override{
        bytes32 transferHash = keccak256(abi.encode(transferData));
        require(validTransferHashes[transferHash] == PENDING_TRANSACTION ,"Transaction Already complete");
        require(transferData.startTime + (MINIMUM_REFUND_DAYS * 1 days) > block.timestamp,"Refund window not started");

        validTransferHashes[transferHash] = COMPLETED_TRANSACTION;

        IERC20(transferData.tokenAddress).safeTransfer(
                transferData.sender,
                transferData.amount + transferData.fee
        );
    }
}