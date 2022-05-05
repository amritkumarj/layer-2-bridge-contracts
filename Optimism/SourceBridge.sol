// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;



import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/DataType.sol";
// import "../common/Patricia.sol";
import {StateProofVerifier as Verifier} from "../common/StateProofVerifier.sol";
import {RLPReader} from "../common/RLPReader.sol";
interface ISource{

    event newTransfer(
        DataType.TransferData transferData
    );
    function transfer(DataType.TransferData memory transferData) external payable;

    function processClaims(DataType.RewardData[] memory rewardDataList) external;
    function refundFunction(DataType.TransferData memory transferData) external;
    function updateStateRoot(bytes32 stateRoot) external;
    function verifyChainHead(bytes memory accountProof, bytes memory storageProof) external;
}
interface OVMLayer2Messenger{
    function xDomainMessageSender() external view returns (address);
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

    OVMLayer2Messenger ovmL2CrossDomainMessenger;
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);
    
    bytes32 destinationStateRoot;
    bytes32 DESTINATION_ADDRESS_HASH;
    bytes32 REWARD_ONION_STORAGE_HASH;
    function undoL1ToL2Alias(address l2Address) internal pure returns (address l1Address) {
        l1Address = address(uint160(l2Address) - offset);
    }

    modifier fromL1Contract(){
        require(
            msg.sender == address(ovmL2CrossDomainMessenger)
            && ovmL2CrossDomainMessenger.xDomainMessageSender() == L1ContractAddress
        );
        _;
    }

   
    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    constructor(address L1Address, address destinationAddress, address ovmCrossDomaniMessenger){
        processedTransferCount = 0;
        processedRewardHashOnion = 0;
        owner = msg.sender;
        L1ContractAddress = L1Address;
        DESTINATION_ADDRESS_HASH = keccak256(abi.encodePacked(destinationAddress));

        ovmL2CrossDomainMessenger = OVMLayer2Messenger(ovmCrossDomaniMessenger);
    }

    function updateL1Address(address L1Address) public onlyOwner{
        L1ContractAddress = L1Address;
    }


    function transfer(DataType.TransferData memory transferData) external payable override {
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
  
    function updateStateRoot(bytes32 stateRoot) external override fromL1Contract{
        destinationStateRoot = stateRoot;
    } 

    function verifyChainHead(bytes memory accountProof, bytes memory storageProof) external override{
        
        Verifier.Account memory desinationAccountPool = Verifier.extractAccountFromProof(
            DESTINATION_ADDRESS_HASH,
           destinationStateRoot,
            RLPReader.toList(RLPReader.toRlpItem(accountProof))
        );

        require(desinationAccountPool.exists, "Desitnation Account not found");

        Verifier.SlotValue memory rewardOnionSlot = Verifier.extractSlotValueFromProof(
            REWARD_ONION_STORAGE_HASH,
            desinationAccountPool.storageRoot,
            RLPReader.toList(RLPReader.toRlpItem(storageProof))
        );

        require(rewardOnionSlot.exists, "Reward Onion value not found");
        knownHashOnions[bytes32(rewardOnionSlot.value)] = true;
    }

    function processClaims(DataType.RewardData[] memory rewardDataList) external override{
        bytes32 tempProcessedRewardHashOnion = processedRewardHashOnion;
        for (uint256 i = 0; i < rewardDataList.length; i++) {
            DataType.RewardData memory rewardData = rewardDataList[i];
            tempProcessedRewardHashOnion = keccak256(abi.encode(tempProcessedRewardHashOnion,keccak256(abi.encode(rewardData))));
        }

        require(knownHashOnions[tempProcessedRewardHashOnion],"Unknown Hash");

        processedRewardHashOnion = tempProcessedRewardHashOnion;

        for (uint256 i = 0; i < rewardDataList.length; i++) {

            DataType.RewardData memory rewardData = rewardDataList[i];
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

    function refundFunction(DataType.TransferData memory transferData) external override{
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