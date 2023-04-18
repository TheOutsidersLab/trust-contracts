import { ethers } from 'hardhat'
import {
  TrustId,
  IexecRateOracle,
  FakeIexecRateOracle,
  Lease, CroesusTokenERC20,
} from '../../typechain-types'

/**
 * Deploys protocol contracts
 */
export async function deploy(): Promise<
  [
    TrustId,
    Lease,
    IexecRateOracle,
    CroesusTokenERC20,
  ]
> {

  //Deploy Oracle
  // const Oracle = await ethers.getContractFactory("IexecRateOracle");
  const Oracle = await ethers.getContractFactory("FakeIexecRateOracle");
  const oracleContract = await Oracle.deploy();
  console.log("Oracle address:", oracleContract.address);

  //Deploy TrustId
  const TrustId = await ethers.getContractFactory("TrustId");
  const trustIdContract = await TrustId.deploy();
  console.log("TrustId address:", trustIdContract.address);

  //Deploy Lease
  const Lease = await ethers.getContractFactory("Lease");
  const leaseArgs: [string, string] = [trustIdContract.address, oracleContract.address]
  const leaseContract = await Lease.deploy(...leaseArgs);
  console.log("Lease address:", leaseContract.address);

  //Add dependency to TenantId contract
  await trustIdContract.updateLeaseContractAddress(leaseContract.address);

  //Deploy CRT token
  const CroesusToken = await ethers.getContractFactory("CroesusTokenERC20");
  const croesusTokenContract = await CroesusToken.deploy();
  const croesusTokenAddress = croesusTokenContract.address;
  console.log("CroesusToken address:", croesusTokenAddress);

  return [
    trustIdContract,
    leaseContract,
    oracleContract,
    croesusTokenContract,
  ]
}
