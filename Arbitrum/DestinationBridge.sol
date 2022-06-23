// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/DataType.sol";

interface IDestination{

    event newTransfer(
        DataType.TransferData transferData
    );
    function claim(DataType.TransferData memory transferData) external payable;

    function getLPFee(uint256 startTime, uint256 fee, uint256 feeRampup) external view returns(uint256);

    function declareNewHashChainHead() external;

}

interface CrossDomainMessenger{

    function sendMessage(
        address _target,
        bytes memory _message,
        uint32 _gasLimit
    ) external ;
}

contract Destination is IDestination{
    using SafeERC20 for IERC20;

    uint8 public constant MINIMUM_REFUND_DAYS = 8;

    uint8 public constant MAX_TRANSACTION_PER_ONION = 100;

    address constant ETH_ADDRESS = address(0);

    mapping(bytes32 => bool) claimedTransferHashes;
    bytes32[] rewardHashOnionHistoryList;
    uint32 MAX_GAS = 3000000;
    bytes32 rewardHashOnion;
    uint256 lastSourceHashPosition;
    uint8 transferCount;
    address owner;

    address L1ContractAddress;
    bytes4 L1selector = bytes4(0x65a622cd);

    CrossDomainMessenger public crossDomainMessenger;
    constructor(address L1Address, address messengerAddress){
        rewardHashOnion = 0;
        transferCount = 0;
        lastSourceHashPosition = 0;
        owner = msg.sender;
        L1ContractAddress = L1Address;
        crossDomainMessenger = CrossDomainMessenger(messengerAddress);
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function changeMessenger(address messengerAddress) public onlyOwner{
        crossDomainMessenger = CrossDomainMessenger(messengerAddress);
    }
    function updateL1Address(address L1Address) public onlyOwner{
        L1ContractAddress = L1Address;
    }

    function getLPFee(uint256 startTime, uint256 fee, uint256 feeRampup) public view override returns (uint256) {
        uint256 currentTime = block.timestamp;
        if(currentTime < startTime){
            return 0;
        }else if(currentTime >= startTime + feeRampup){
            return fee;
        }else {
            return fee * (currentTime - startTime) / feeRampup;
        }
    }

    
    function claim(DataType.TransferData memory transferData) external payable override {
        uint256 amountMinusLPFee = transferData.amount - getLPFee(transferData.startTime,transferData.fee,transferData.feeRampup); 
        require(amountMinusLPFee >= 0.001 ether);
        bytes32 transferHash = keccak256(abi.encode(transferData));
        require(!claimedTransferHashes[transferHash],"Already Claimed");


        if(transferData.tokenAddress == ETH_ADDRESS){
            require(msg.value + tx.gasprice == amountMinusLPFee);

            claimedTransferHashes[transferHash] = true;
            DataType.RewardData memory rewardData = DataType.RewardData(transferHash,transferData.tokenAddress,msg.sender,transferData.amount);
            rewardHashOnion = keccak256(abi.encode(rewardHashOnion,keccak256(abi.encode(rewardData))));
            transferCount += 1;
            if(transferCount % MAX_TRANSACTION_PER_ONION == 0){
                rewardHashOnionHistoryList.push(rewardHashOnion);
            }
            payable(transferData.destination).transfer(amountMinusLPFee);

            emit newTransfer(transferData);

            return;
            
        }else{
           
            IERC20(transferData.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amountMinusLPFee
            );
            claimedTransferHashes[transferHash] = true;

            DataType.RewardData memory rewardData = DataType.RewardData(transferHash,transferData.tokenAddress,msg.sender,transferData.amount);
            rewardHashOnion = keccak256(abi.encode(rewardHashOnion,keccak256(abi.encode(rewardData))));
            transferCount += 1;
            if(transferCount % MAX_TRANSACTION_PER_ONION == 0){
                rewardHashOnionHistoryList.push(rewardHashOnion);
            }    
            IERC20(transferData.tokenAddress).safeTransfer(
                transferData.destination,
                amountMinusLPFee
            );

            emit newTransfer(transferData);

            return;
        }
    }
  

    function declareNewHashChainHead() external override{
        uint256 currentListLength = rewardHashOnionHistoryList.length;
        require(lastSourceHashPosition < currentListLength,"No new hashOnion");
        uint256 onionLength = (currentListLength - lastSourceHashPosition) + 1;
        bytes32[] memory rewardHashOnions = new bytes32[](onionLength);
        for(uint256 i = lastSourceHashPosition;i < rewardHashOnionHistoryList.length;i++){
            rewardHashOnions[i - lastSourceHashPosition] = rewardHashOnionHistoryList[i];
        }
        rewardHashOnions[onionLength-1] = rewardHashOnion;
        
        bytes memory message = abi.encodeWithSelector(L1selector, rewardHashOnions);
        crossDomainMessenger.sendMessage(L1ContractAddress,message,MAX_GAS);
        lastSourceHashPosition = currentListLength;
    }

}