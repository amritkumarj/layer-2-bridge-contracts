// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

// DATA FLOW : ARBITRUM L2(DEST) -> L1 -> OPTIMISM L2(SOURCE)

interface OVMLayer1Messenger{
    function xDomainMessageSender() external view returns (address);
    function sendMessage(
        address _target,
        bytes memory _message,
        uint32 _gasLimit
    ) external; 
}

contract BondingContract{
    address sourceAddress;
    address destinationAddress;
    address owner;
    uint32 maxGas = 1000000;
    bytes4 sourceSelector = bytes4(0xacaf80a1);
    OVMLayer1Messenger ovmMessenger;
    constructor(address sourceContractAddress, address destinationContractAddress, address ovmMessengerAddress){
        sourceAddress = sourceContractAddress;
        destinationAddress = destinationContractAddress;
        ovmMessenger = OVMLayer1Messenger(ovmMessengerAddress);
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

    function updateOVMMessengerAddress(address ovmAddress) public onlyOwner{
        ovmMessenger = OVMLayer1Messenger(ovmAddress);
    }
    function updateSourceSelector(bytes4 selector) public onlyOwner{
        sourceSelector = selector;
    }

    //TODO - Get State root from L1 Destination Rollup Contract
    function getDestinationStateRoot() internal view returns (bytes32 stateRoot){

    }

    function passStateRoot() public payable{

        bytes32 stateRoot = getDestinationStateRoot();
        ovmMessenger.sendMessage(
            sourceAddress,
            abi.encodeWithSelector(
                sourceSelector,
                stateRoot
            ),
            maxGas
        );
    }

}