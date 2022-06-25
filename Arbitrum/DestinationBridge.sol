// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/DataType.sol";

interface IDestination{

    event NewTransfer(
        DataType.TransferData transferData
    );
    function claim(DataType.TransferData memory transferData) external payable;

    function getLPFee(uint256 startTime, uint256 fee, uint256 feeRampup) external view returns(uint256);

    function declareNewHashChainHead() external;

}

interface ArbSys{

    function sendTxToL1(address destination, bytes calldata calldataForL1) external payable returns(uint);
}

contract Destination is IDestination{
    using SafeERC20 for IERC20;

    uint8 public constant MINIMUM_REFUND_DAYS = 8;

    uint8 public  MAX_TRANSACTION_PER_ONION = 100;

    address constant ETH_ADDRESS = address(0);

    event TransferRewardHashOnion(
        uint256 index
    );

    mapping(bytes32 => bool) claimedTransferHashes;
    bytes32[] rewardHashOnionHistoryList;
    uint32 MAX_GAS = 3000000;
    bytes32 rewardHashOnion;
    uint256 lastSourceHashPosition;
    uint8 transferCount;
    address owner;

    address L1ContractAddress;
    bytes4 L1selector = bytes4(0x65a622cd);
    uint256 MINIMUM_TRANSFER = 0.001 ether;

    ArbSys public arbSys;
    constructor(address L1Address, address arbSysAddress){
        rewardHashOnion = 0;
        transferCount = 0;
        lastSourceHashPosition = 0;
        owner = msg.sender;
        L1ContractAddress = L1Address;
        arbSys = ArbSys(arbSysAddress);
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function changeMessenger(address arbSysAddress) public onlyOwner{
        arbSys = ArbSys(arbSysAddress);
    }
    function updateL1Address(address L1Address) public onlyOwner{
        L1ContractAddress = L1Address;
    }

    function updateMaxTransactions(uint8 newMaxTransaction) public onlyOwner{
        MAX_TRANSACTION_PER_ONION = newMaxTransaction;
    }

    function getLPFee(uint256 startTime, uint256 fee, uint256 feeRampup) public view override returns (uint256) {
        uint256 currentTime = block.timestamp;
        if(currentTime < startTime){
            return 0;
        }else if(currentTime >= startTime + feeRampup){
            return fee;
        } else {
            return (fee * (100 + (feeRampup - (currentTime - startTime)))) / 100;
        }
    }

    
    function claim(DataType.TransferData memory transferData) external payable override {
        uint256 amountMinusLPFee = transferData.amount - getLPFee(transferData.startTime,transferData.fee,transferData.feeRampup); 
        require(amountMinusLPFee >= MINIMUM_TRANSFER);
        bytes32 transferHash = keccak256(abi.encode(transferData));
        require(!claimedTransferHashes[transferHash],"Already Claimed");

        if(transferData.tokenAddress == ETH_ADDRESS){
            require(msg.value == amountMinusLPFee);

            claimedTransferHashes[transferHash] = true;
            DataType.RewardData memory rewardData = DataType.RewardData(transferHash,transferData.tokenAddress,msg.sender,transferData.amount);
            rewardHashOnion = keccak256(abi.encode(rewardHashOnion,keccak256(abi.encode(rewardData))));
            
            payable(transferData.destination).transfer(amountMinusLPFee);
            transferCount += 1;
            if(transferCount % MAX_TRANSACTION_PER_ONION == 0){
                rewardHashOnionHistoryList.push(rewardHashOnion);
            }
            emit NewTransfer(transferData);

        }else{
            IERC20(transferData.tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amountMinusLPFee
            );
            claimedTransferHashes[transferHash] = true;

            DataType.RewardData memory rewardData = DataType.RewardData(transferHash,transferData.tokenAddress,msg.sender,transferData.amount);
            rewardHashOnion = keccak256(abi.encode(rewardHashOnion,keccak256(abi.encode(rewardData))));
                
            IERC20(transferData.tokenAddress).safeTransfer(
                transferData.destination,
                amountMinusLPFee
            );

            transferCount += 1;
            if(transferCount % MAX_TRANSACTION_PER_ONION == 0){
                rewardHashOnionHistoryList.push(rewardHashOnion);
            }
            emit NewTransfer(transferData);
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
        uint256 id = arbSys.sendTxToL1(L1ContractAddress,message);
        emit TransferRewardHashOnion(id);
        lastSourceHashPosition = currentListLength;
    }

}