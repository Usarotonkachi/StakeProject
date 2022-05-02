let secret = require("./secret")

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-tracer");

const { API_URL, PRIVATE_KEY, ETHERSCAN_KEY} = process.env;


module.exports = {
  solidity: "0.8.4",
  networks: {
    testnet: {
      url: secret.url,
      accounts: [secret.key],
      gas: 2100000,
    gasPrice: 8000000000
    },
    rinkeby: {
      url: "https://speedy-nodes-nyc.moralis.io/26e50ab044cfb048e9442a7f/eth/rinkeby",
      accounts: [secret.key]
      
    }
  },
  etherscan: {
      apiKey: "2VWZ6QW8WI6GCWTKMP774DQBX2WPE3D882"
  }
};