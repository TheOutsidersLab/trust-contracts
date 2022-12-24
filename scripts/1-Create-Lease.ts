import { ethers } from 'hardhat'
import {ConfigAddresses} from "../contract-addresses";
import { getCurrentTimestamp } from "hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp";

const hre = require('hardhat')

async function main() {
  const network = await hre.network.name
  console.log(network)
  console.log('Create fake data')

  const [alice, bob, carol, dave] = await ethers.getSigners()
  console.log('alice', alice.address)

  const ownerIdContract = await ethers.getContractAt(
    'OwnerId',
    ConfigAddresses.ownerIdAddress,
  )
  console.log('ownerIdContract', ownerIdContract.address)

  const tenantIdContract = await ethers.getContractAt(
    'TenantId',
    ConfigAddresses.tenantIdAddress,
  )
  console.log('tenantIdContract', tenantIdContract.address)

  const leaseContract = await ethers.getContractAt(
    'Lease',
    ConfigAddresses.leaseAddress,
  )
  console.log('leaseContract', leaseContract.address)

  const createLeaseTx = await leaseContract.connect(alice).createLease(
    await tenantIdContract.getUserId(alice.address),
    ethers.utils.parseEther('0.000000005'),
    ethers.constants.AddressZero,
    '12',
    0,
    0,
    'CRYPTO',
    getCurrentTimestamp(),
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
