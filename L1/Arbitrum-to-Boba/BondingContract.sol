// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

// DATA FLOW : ARBITRUM L2(DEST) -> L1 -> BOBA NETWORK L2(SOURCE)

interface L1CrossDomainManager{
    function sendMessage(
        address _target,
        bytes memory _message,
        uint32 _gasLimit
    ) external; 
}
interface IOutbox {

    function l2ToL1Sender() external view returns (address);

}

contract BondingContract{
    address sourceAddress;
    address destinationAddress;
    address owner;
    uint32 maxGas = 1000000;
    bytes4 sourceSelector = bytes4(0x81b24111);
    L1CrossDomainManager messenger;

    IOutbox outbox;
    constructor(address sourceContractAddress, address destinationContractAddress,  address arbOutbox, address l1Messenger){
        sourceAddress = sourceContractAddress;
        destinationAddress = destinationContractAddress;
        outbox = IOutbox(arbOutbox);
        messenger = L1CrossDomainManager(l1Messenger);
        owner = msg.sender;
    }
    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    function updateDestinationAddress(address destAddress) public onlyOwner{
        destinationAddress = destAddress;
    }

    function updateSourceAddress(address SourceAddress) public onlyOwner{
        sourceAddress = SourceAddress;
    }

    function updateOutbox(address arbOutbox) public onlyOwner{
        outbox = IOutbox(arbOutbox);
    }

    function updateMessenger(address l1Messenger) public onlyOwner{
        messenger = L1CrossDomainManager(l1Messenger);
    }

    function updateSourceSelector(bytes4 selector) public onlyOwner{
        sourceSelector = selector;
    }

    modifier fromDestinationContract(){
        require(
            msg.sender == address(outbox)
            && outbox.l2ToL1Sender() == destinationAddress
        );
        _;
    }
    
    function passData(bytes32[] memory rewardHashList) public fromDestinationContract{
        
        messenger.sendMessage(
            sourceAddress,
            abi.encodeWithSelector(
                sourceSelector,
                rewardHashList
            ),
            maxGas
        );
    }

}