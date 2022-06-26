// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.7;

import "../../interfaces/IBonding.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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


contract BondingContract is IBonding,Initializable {
    address sourceAddress;
    address destinationAddress;
    address owner;

    address arbBridge;
    uint32 maxGas;
    bytes4 sourceSelector;
    L1CrossDomainManager messenger;

    IOutbox outbox;
    function initialize(address sourceContractAddress, address destinationContractAddress,  address arbOutbox, address l1Messenger, address bridge) external initializer{
        sourceAddress = sourceContractAddress;
        destinationAddress = destinationContractAddress;
        outbox = IOutbox(arbOutbox);
        messenger = L1CrossDomainManager(l1Messenger);
        arbBridge = bridge;
        owner = msg.sender;
        maxGas = 1000000;
        sourceSelector = bytes4(0x81b24111);
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
            msg.sender == arbBridge
            && outbox.l2ToL1Sender() == destinationAddress
        );
        _;
    }
    
    function passData(bytes32[] memory rewardHashList) public fromDestinationContract override{
        
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