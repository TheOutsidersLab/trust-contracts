import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {TrustId, Lease, IexecRateOracle, CroesusTokenERC20, FakeIexecRateOracle} from "../typechain-types";
import {deploy} from "./utils/deploy";

describe("Trust", function () {
  let deployer: SignerWithAddress,
    alice: SignerWithAddress,
    bob: SignerWithAddress,
    carol: SignerWithAddress,
    dave: SignerWithAddress,
    eve: SignerWithAddress,
    frank: SignerWithAddress,
    grace: SignerWithAddress,
    heidi: SignerWithAddress,
    trustIdContract: TrustId,
    leaseContract: Lease,
    croesusTokenContract: CroesusTokenERC20,
    fakeIexecRateOracle: FakeIexecRateOracle,
    IexecRateOracle: IexecRateOracle,
    chainId: number

  const ALICE_ID = 1;
  const DUMMY_CONTRACT_ADDRESS = '0x3F87289e6Ec2D05C32d8A74CCfb30773fF549306';

  before(async function () {
    // Get the Signers
    [deployer, alice, bob, carol, dave, eve, frank, grace, heidi] = await ethers.getSigners();
    [trustIdContract, leaseContract, fakeIexecRateOracle, croesusTokenContract] = await deploy();

    // Transfer tokens to all signers
    await croesusTokenContract.transfer(alice.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(bob.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(carol.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(dave.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(eve.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(frank.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(grace.address, ethers.utils.parseEther('1000'))
    await croesusTokenContract.transfer(heidi.address, ethers.utils.parseEther('1000'))
  });

describe("TrustId Contract Test", function () {
    it("Only Deployer can update Lease Contract address", async function () {
      const tx = trustIdContract.connect(alice).updateLeaseContractAddress(DUMMY_CONTRACT_ADDRESS);
      await expect(tx).to.be.revertedWith('Ownable: caller is not the owner');
      const leaseContractAddress = trustIdContract.address;
      const tx2 = await trustIdContract.connect(deployer).updateLeaseContractAddress(DUMMY_CONTRACT_ADDRESS);
      // await expect(tx2).to.emit(trustIdContract, "UpdateLeaseContractAddress").withArgs(DUMMY_CONTRACT_ADDRESS);
      await expect(tx2).not.to.be.reverted;
      // Reset address to original
      await trustIdContract.connect(deployer).updateLeaseContractAddress(leaseContractAddress);
    });

    it("Alice can mint an ID", async function () {
      const tx = await trustIdContract.connect(alice).mint("alice");
      await expect(tx).to.emit(trustIdContract, "Mint").withArgs(alice.address, ALICE_ID, "alice");
      expect(await trustIdContract.connect(alice).ids(alice.address)).to.be.equal(ALICE_ID);
    });

    it("Alice can check her balance", async function () {
      expect(await trustIdContract.connect(alice).balanceOf(alice.address)).to.be.equal(1);
    });

    it("Alice can't mint a second id", async function () {
      const tx = trustIdContract.connect(alice).mint("alice");
      await expect(tx).to.be.revertedWith('You already have a User Id')
    });

    it("Alice can't transfer her ID", async function () {
      const tx = trustIdContract.connect(alice).transferFrom(alice.address, bob.address, ALICE_ID);
      expect(await trustIdContract.connect(alice).ids(alice.address)).to.be.equal(ALICE_ID);
    });

    it("Alice can update her profile", async function () {
      const tx = await trustIdContract.connect(alice).updateProfileData(ALICE_ID, 'cid');
      await expect(tx).to.emit(trustIdContract, "CidUpdated").withArgs(ALICE_ID, 'cid');
      // expect(await trustIdContract.connect(alice).profiles(ALICE_ID)).to.be.equal('cid');
    });

    it("Should not be possible for Bob to update her profile", async function () {
      const tx = trustIdContract.connect(bob).updateProfileData(ALICE_ID, 'cid');
      await expect(tx).to.be.revertedWith('UserId: caller is not the owner')
    });
  });
});
