import { ethers } from 'hardhat'
import {ConfigAddresses} from "../contract-addresses";
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

  const mintTx = await ownerIdContract.connect(alice).mint('alice');
  await mintTx.wait();
  console.log('Alice ownerId: ', await ownerIdContract.getOwnerIdFromAddress(alice.address))

  const mintTx2 = await ownerIdContract.connect(bob).mint('bob');
  await mintTx2.wait();
  console.log('Bob ownerId: ', await ownerIdContract.getOwnerIdFromAddress(bob.address))

  const mintTx3 = await tenantIdContract.connect(carol).mint('carol');
  await mintTx3.wait();
  console.log('Carol tenantId: ', await tenantIdContract.getUserId(carol.address))

  const mintTx4 = await tenantIdContract.connect(dave).mint('dave');
  await mintTx4.wait();
  console.log('Dave tenantId: ', await tenantIdContract.getUserId(dave.address));

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
