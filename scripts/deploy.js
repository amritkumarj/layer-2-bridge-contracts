const hre = require("hardhat");
const DUMMY_ADDRESS = "0x0000000000000000000000000000000000000000"
const ARBSYS_ADDRESS = "0x0000000000000000000000000000000000000064"
const BOBA_OVM_CROSS_DOMAIN_MESSENGER_L2 = "0x4200000000000000000000000000000000000007"
const ARB_OUTBOX_L1 = "0x2360A33905dc1c72b12d975d975F42BaBdcef9F3"
const BOBA_MESSENGER_L1 = "0xF10EEfC14eB5b7885Ea9F7A631a21c7a82cf5D76"


const ARBITRUM_NETWORK = "arbitrum_rinkeby"
const BOBA_NETWORK = "boba_rinkeby"
const ETH_NETWORK = "rinkeby"

async function main() {
    await deployBobaArbitrumBridge()
}
async function deployBobaArbitrumBridge(){

  hre.changeNetwork(ARBITRUM_NETWORK);
  const DestinationBridge = await hre.ethers.getContractFactory("DestinationBridge");
  const destinationBridge =  await hre.upgrades.deployProxy(DestinationBridge, [
    DUMMY_ADDRESS,
    ARBSYS_ADDRESS
  ], {initializer: 'initialize',unsafeAllow: ['delegatecall']});
  await destinationBridge.deployed()
  console.log("Destination Bridge address: ", destinationBridge.address);


  hre.changeNetwork(BOBA_NETWORK);
  const SourceBridge = await hre.ethers.getContractFactory("SourceBridge");
  const sourceBridge =  await hre.upgrades.deployProxy(SourceBridge, [
    DUMMY_ADDRESS,
    BOBA_OVM_CROSS_DOMAIN_MESSENGER_L2
  ], {initializer: 'initialize',unsafeAllow: ['delegatecall']});
  await sourceBridge.deployed()
  console.log("Source Bridge address: ", sourceBridge.address); 


  hre.changeNetwork(ETH_NETWORK);
  const BondingContract = await hre.ethers.getContractFactory("BondingContract");
  const bondingContract =  await hre.upgrades.deployProxy(BondingContract, [
    sourceBridge.address,
    destinationBridge.address,
    ARB_OUTBOX_L1,
    BOBA_MESSENGER_L1
  ], {initializer: 'initialize',unsafeAllow: ['delegatecall']});
  await bondingContract.deployed()
  console.log("Bonding Contract address: ", bondingContract.address);

  await destinationBridge.updateL1Address(bondingContract.address)
  await sourceBridge.updateL1Address(bondingContract.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });