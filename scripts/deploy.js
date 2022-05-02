const hre = require("hardhat");
const ethers = hre.ethers;

async function main() {
  const StakeTokens = await ethers.getContractFactory("StakeTokens");
  const stakeTokens = await StakeTokens.deploy("0x1ecb6C205Dcd32833D7095B994525d47532bE1cf");

  await stakeTokens.deployed();
  
  console.log("RewardToken deployed to address: ", stakeTokens.address);
  console.log("RewardToken deployed to block: ", await hre.ethers.provider.getBlockNumber());
  console.log("RewardToken owner is: ", await (stakeTokens.provider.getSigner() ).getAddress() );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });