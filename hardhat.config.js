/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("hardhat-change-network");
require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-waffle');
require('@openzeppelin/hardhat-upgrades');

const privateKey = "a7e70ea0d6f2cb6501488148fd280cd8a2047af7ecd5197c238692736eecb7fc"
module.exports = {
  solidity: "0.8.7",
  networks: {
    hardhat: {
    },
    rinkeby: {
      url: "https://rinkeby.infura.io/v3/4d82bd025208490993c4d94e829018eb",
      accounts: [privateKey]
    },
    boba_rinkeby: {
      url: "https://rinkeby.boba.network/",
      accounts: [privateKey]
    },
    arbitrum_rinkeby: {
      url: "https://rinkeby.arbitrum.io/rpc",
      accounts: [privateKey]
    }
  },
};
