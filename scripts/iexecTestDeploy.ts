import {task} from "hardhat/config";
import {ethers} from "hardhat";
import {getCurrentTimestamp} from "hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp";

//npx hardhat deploy --normal-rent --network localhost
//npx hardhat iexec --network goerli
task("iexec", "Deploys Iexec oracle")
  .setAction(async (taskArgs, {ethers, run}) => {
    const [deployer, croseus, brutus, maximus, marcusAurelius] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    await run("compile");

    //Deploy OwnerId
    const IexecOracle = await ethers.getContractFactory("IexecRateOracle");
    const iexecContract = await IexecOracle.deploy();
    const iexecAddress = iexecContract.address;
    console.log("Oracle address:", iexecAddress);
    // console.log("Oracle contract:", iexecContract);
    // const iexecContract = await ethers.getContractAt("IexecRateOracle", "0xBDe91934345F070AfC86C208Fe0a787F44ee0D1C", deployer);
    // console.log("Oracle address:", iexecContract.address);



    const oracleValue = await iexecContract.connect(deployer).getRate('USD-ETH');
    // const oraclezdzdValue = await iexecContract.connect(deployer).addOracle('USD-ETH', '0xf0f370ad33d1e3e8e2d8df7197c40f62b5bc403553b103858359687491234491');
    // oracleValue.wait();
    console.log('Oracle value: ', oracleValue);

    // const oracleValue = await iexecContract.connect(deployer).getOracleData('0x26c07660a5c927218dc3ac5519d2b7d35ff66ac239466e12cd2518ebcded77e3');
    //   ethers.utils.formatBytes32String('0xf0f370ad33d1e3e8e2d8df7197c40f62b5bc403553b103858359687491234491'));
    // console.log('Oracle value: ', oracleValue);
  });