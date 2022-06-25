// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/DataType.sol";
import "../interfaces/ISource.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface OVMLayer2Messenger{
    function xDomainMessageSender() external view returns (address);
}
contract SourceBridge is ISource,Initializable {
    using SafeERC20 for IERC20;
    uint8 public constant NEW_TRANSACTION = 0;
    uint8 public constant PENDING_TRANSACTION = 1;
    uint8 public constant COMPLETED_TRANSACTION = 2;
    uint8 public constant MINIMUM_REFUND_DAYS = 8;

    address constant ETH_ADDRESS = address(0);

    mapping(bytes32 => uint8) public validTransferHashes;
    mapping(bytes32 => bool) public knownHashOnions;

    bytes32 public processedRewardHashOnion;
    uint256 public processedTransferCount;
    address public owner;
    address public L1ContractAddress;
    OVMLayer2Messenger public ovmL2CrossDomainMessenger;
    
    uint256 nonce;
    uint256 MINIMUM_TRANSFER;
    uint8 CONTRACT_FEE_BASIS_POINTS;

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

    function initialize(address L1Address, address ovmCrossDomaniMessenger) external initializer{
        processedTransferCount = 0;
        processedRewardHashOnion = 0;
        nonce = 0;
        owner = msg.sender;
        L1ContractAddress = L1Address;

        ovmL2CrossDomainMessenger = OVMLayer2Messenger(ovmCrossDomaniMessenger);

        MINIMUM_TRANSFER = 0.001 ether;
        CONTRACT_FEE_BASIS_POINTS = 5;
    }

    function updateL1Address(address L1Address) public onlyOwner{
        L1ContractAddress = L1Address;
    }

    function updateMessenger(address messenger) public onlyOwner{
        ovmL2CrossDomainMessenger = OVMLayer2Messenger(messenger);
    }

    function updateContractFee(uint8 contractFee) public onlyOwner{
        CONTRACT_FEE_BASIS_POINTS = contractFee;
    }

    function getLPFees(uint256 amount) public view override returns(uint256 fee,uint256 amountPlusFee){
         amountPlusFee = (amount * (10000 + CONTRACT_FEE_BASIS_POINTS)) / 10000; 
         fee = amountPlusFee - amount;
    }

    function transfer(address tokenAddress, address destination, uint256 amount, uint256 feeRampup) external payable override {
         (uint256 fee,uint256 amountPlusFee) = getLPFees(amount);
        uint256 newNonce = nonce + 1;
        require(amountPlusFee >= MINIMUM_TRANSFER);

        DataType.TransferData memory transferData = DataType.TransferData(
            tokenAddress,
            destination,
            msg.sender,
            amountPlusFee,
            fee,
            block.timestamp,
            feeRampup,
            newNonce
        );
        bytes32 transferHash = keccak256(abi.encode(transferData));

        require(validTransferHashes[transferHash] == NEW_TRANSACTION);
        if(transferData.tokenAddress == ETH_ADDRESS){
            require(msg.value == amountPlusFee);
            validTransferHashes[transferHash] = PENDING_TRANSACTION;
            nonce = newNonce;
            emit NewTransfer(transferData);
        }else{
            IERC20(transferData.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amountPlusFee
            );

            validTransferHashes[transferHash] = PENDING_TRANSACTION;
            nonce = newNonce;
            emit NewTransfer(transferData);
        }
    }
  

    function declareNewHashChainHead(bytes32[] memory newOnionHashes) external override fromL1Contract{
        for (uint256 i = 0; i < newOnionHashes.length; i++) {
            bytes32 newOnionHash = newOnionHashes[i];
            knownHashOnions[newOnionHash] = true;
        }
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