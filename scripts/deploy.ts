import { task } from 'hardhat/config'
import { ethers } from 'hardhat'
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp'

// npx hardhat deploy --fiat-rent-payment-eth --fiat-rent-payment-token --crypto-rent --open-lease --network localhost
task('deploy', 'Deploys contracts')
  .addFlag('cryptoRent', 'Rents paid & not paid in ETH')
  .addFlag('alreadyDeployed', 'If contracts already deployed')
  .addFlag('fiatRentPaymentToken', 'Rents in fiat payment in token')
  .addFlag('fiatRentPaymentEth', 'Rents in fiat payment in token')
  .addFlag('cancelLease', 'Rents paid & not paid & lease is cancelled')
  .addFlag('openLease', 'OpenLease workflow')
  .setAction(async (taskArgs, { ethers, run }) => {
    const cid = 'QmXtXJnM3FGD6q4unEo7A2RyXBrBrbQsr6MawEQAwiyN85'
    const { cryptoRent, cancelLease, fiatRentPaymentToken, fiatRentPaymentEth, openLease } =
      taskArgs
    const [deployer, croesus, brutus, maximus, aurelius] = await ethers.getSigners()
    let leaseIdCounter = 1
    console.log('Deploying contracts with the account:', deployer.address)
    await run('compile')

    //Deploy PlatformId
    const PlatformId = await ethers.getContractFactory('PlatformId')
    const platformIdContract = await PlatformId.deploy()
    console.log('PlatformId address:', platformIdContract.address)

    //Deploy Oracle
    // const Oracle = await ethers.getContractFactory("IexecRateOracle");
    const Oracle = await ethers.getContractFactory('FakeIexecRateOracle')
    const oracleContract = await Oracle.deploy()
    console.log('Oracle address:', oracleContract.address)

    //Deploy TrustId
    const TrustId = await ethers.getContractFactory('TrustId')
    const trustIdContract = await TrustId.deploy()
    console.log('TrustId address:', trustIdContract.address)

    //Deploy Lease
    const Lease = await ethers.getContractFactory('Lease')
    const leaseArgs: [string, string] = [trustIdContract.address, platformIdContract.address]
    const leaseContract = await Lease.deploy(...leaseArgs)
    console.log('Lease address:', leaseContract.address)

    //Deploy PaymentManager
    const PaymentManager = await ethers.getContractFactory('PaymentManager')
    const paymentManagerArgs: [string, string, string, string] = [
      trustIdContract.address,
      oracleContract.address,
      platformIdContract.address,
      leaseContract.address,
    ]
    const paymentManagerContract = await PaymentManager.deploy(...paymentManagerArgs)
    console.log('PaymentManager address:', paymentManagerContract.address)

    //Add dependency to TenantId contract
    await trustIdContract.updateLeaseContractAddress(leaseContract.address)

    //Deploy CRT token
    const CroesusToken = await ethers.getContractFactory('CroesusTokenERC20')
    const croesusToken = await CroesusToken.deploy()
    const croesusTokenAddress = croesusToken.address
    console.log('CroesusToken address:', croesusTokenAddress)

    await croesusToken.transfer(brutus.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(maximus.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(aurelius.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(croesus.address, ethers.utils.parseEther('1000'))

    // // UNCOMMENT IF DEPLOYED
    // const oracleContract = await ethers.getContractAt('IexecRateOracle', ConfigAddresses.oracleAddress,)
    // console.log('IexecRateOracle', oracleContract.address)
    //
    // const croesusToken = await ethers.getContractAt('CroesusTokenERC20', ConfigAddresses.croesusToken,)
    // const croesusTokenAddress = croesusToken.address;
    // console.log('ownerIdContract', croesusTokenAddress)
    //
    // const tenantIdContract = await ethers.getContractAt('TenantId', ConfigAddresses.tenantIdAddress,)
    // console.log('tenantIdContract', tenantIdContract.address)
    //
    // const ownerIdContract = await ethers.getContractAt(
    //   'OwnerId',
    //   ConfigAddresses.ownerIdAddress,
    // )
    // console.log('ownerIdContract', ownerIdContract.address)
    //
    // const leaseContract = await ethers.getContractAt('Lease', ConfigAddresses.leaseAddress,)
    // console.log('leaseContract', leaseContract.address)

    // ********************* Contract Calls *************************

    // Grant PaymentManager Role to PaymentManager
    const paymentManagerRole = await leaseContract.PAYMENT_MANAGER_ROLE()
    await leaseContract
      .connect(deployer)
      .grantRole(paymentManagerRole, paymentManagerContract.address)

    // Mint PlatformIds
    const mintTxPlatformId = await platformIdContract.connect(deployer).mint('anywhere')
    await mintTxPlatformId.wait()
    const anywherePlatformId = await platformIdContract.ids(deployer.address)
    console.log('PlatformId: ', anywherePlatformId)
    console.log('For platform: ', (await platformIdContract.platforms(anywherePlatformId))['1'])

    await paymentManagerContract.connect(deployer).updateProtocolWallet(deployer.address)
    await paymentManagerContract.connect(deployer).updateProtocolFeeRate(1000)

    await platformIdContract.connect(deployer).updateOriginLeaseFeeRate(1, 2000)

    // Mint User ids & Give Owner Privileges
    const mintTxDeployerUser = await trustIdContract.connect(deployer).mint('TheBoss')
    await mintTxDeployerUser.wait()
    const deployerUserId = await trustIdContract.ids(deployer.address)
    console.log('TheBoss userId: ', deployerUserId)

    const mintTxCroesusUser = await trustIdContract.connect(croesus).mint('Croesus')
    await mintTxCroesusUser.wait()
    const croesusUserId = await trustIdContract.ids(croesus.address)
    console.log('Croesus userId: ', croesusUserId)

    const mintTxBrutusUser = await trustIdContract.connect(brutus).mint('Brutus')
    await mintTxBrutusUser.wait()
    const brutusUserId = await trustIdContract.ids(brutus.address)
    console.log('Brutus userId: ', brutusUserId)

    const mintTxMaximusUser = await trustIdContract.connect(maximus).mint('Maximus')
    await mintTxMaximusUser.wait()
    const maximusUserId = await trustIdContract.ids(maximus.address)
    console.log('Maximus userId: ', maximusUserId)

    const mintTxAureliusUser = await trustIdContract.connect(aurelius).mint('Aurelius')
    await mintTxAureliusUser.wait()
    const aureliusUserId = await trustIdContract.ids(aurelius.address)
    console.log('Aurelius userId: ', aureliusUserId)

    // console.log('Aurelius profil: ', await tenantIdContract.getTenant('2'));

    if (cryptoRent) {
      //Create lease for ETH payment
      const createLeaseTx = await leaseContract.connect(croesus).createLease(
        // '4',
        croesusUserId,
        maximusUserId,
        ethers.utils.parseEther('0.0000000000005'),
        '12',
        ethers.constants.AddressZero,
        1,
        'CRYPTO',
        getCurrentTimestamp(),
        anywherePlatformId,
        cid,
      )
      await createLeaseTx.wait()
      // console.log('Lease created: ', await leaseContract.leases(1))

      //Validate Lease
      const validateLeaseTx = await leaseContract.connect(maximus).validateLease(maximusUserId, 1)
      await validateLeaseTx.wait()
      const lease = await leaseContract.leases(leaseIdCounter)
      console.log('Lease validated: ', lease.status)

      // //Reject Lease
      // const rejectLeaseTx = await leaseContract.connect(carol).declineLease(1);
      // await rejectLeaseTx.wait();
      // const lease = await leaseContract.leases(1)
      // console.log('Lease Declined: ', lease.status)
      //
      // const hasLease = await tenantIdContract.userHasLease(await tenantIdContract.ids(carol.address));
      // console.log('Maximus has lease: ', hasLease);

      //Maximus pays 12 rents
      for (let i = 0; i < 12; i++) {
        const payRentTx = await paymentManagerContract
          .connect(maximus)
          .payCryptoRent(maximusUserId, leaseIdCounter, i, true, {
            value: ethers.utils.parseEther('0.0000000000005'),
          })
        await payRentTx.wait()
        console.log('Maximus paid rent: ', i)
      }

      const reviewLeaseTx = await leaseContract
        .connect(maximus)
        .reviewLease(maximusUserId, leaseIdCounter, 'TenantReviewURI')
      await reviewLeaseTx.wait()
      console.log('Maximus reviewed lease: ', leaseIdCounter)
      const reviewLeaseTx2 = await leaseContract
        .connect(croesus)
        .reviewLease(croesusUserId, leaseIdCounter, 'OwnerReviewURI')
      await reviewLeaseTx2.wait()
      console.log('Croesus reviewed lease: ', leaseIdCounter)
    }

    if (cryptoRent) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12)
      await croesusToken
        .connect(aurelius)
        .approve(paymentManagerContract.address, totalAmountToApprove)

      //Create token lease
      const createLeaseTx = await leaseContract.connect(croesus).createLease(
        // '4',
        await trustIdContract.ids(croesus.address),
        await trustIdContract.ids(aurelius.address),
        ethers.utils.parseEther('0.0000000000005'),
        '12',
        croesusTokenAddress,
        2,
        'CRYPTO',
        getCurrentTimestamp(),
        anywherePlatformId,
        cid,
      )
      await createLeaseTx.wait()
      leaseIdCounter++
      // console.log('Lease created: ', await leaseContract.leases(leaseIdCounter))

      //Validate token Lease
      const validateLeaseTx = await leaseContract
        .connect(aurelius)
        .validateLease(aureliusUserId, leaseIdCounter)
      await validateLeaseTx.wait()
      const lease = await leaseContract.leases(leaseIdCounter)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 12 rents
      for (let i = 0; i < 12; i++) {
        const payRentTx = await paymentManagerContract
          .connect(aurelius)
          .payCryptoRent(aureliusUserId, leaseIdCounter, i, true)
        await payRentTx.wait()
        console.log('Aurelius paid rent: ', i)
      }

      const reviewLeaseTx = await leaseContract
        .connect(aurelius)
        .reviewLease(aureliusUserId, leaseIdCounter, 'TenantReviewURI')
      await reviewLeaseTx.wait()
      console.log('Aurelius reviewed lease: ', leaseIdCounter)
      const reviewLeaseTx2 = await leaseContract
        .connect(croesus)
        .reviewLease(croesusUserId, leaseIdCounter, 'OwnerReviewURI')
      await reviewLeaseTx2.wait()
      console.log('Croesus reviewed lease: ', leaseIdCounter)
    }

    if (fiatRentPaymentToken) {
      await oracleContract.updateRate('EUR-ETH')
      await oracleContract.updateRate('USD-ETH')
      await oracleContract.updateRate('USD-SHI')
      // const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      // await croesusToken.connect(aurelius).approve(paymentManagerContract.address, totalAmountToApprove);
      const aureliusId = await trustIdContract.ids(aurelius.address)
      console.log('Aurelius id ', aureliusId)

      //Create token lease
      const createLeaseTx = await leaseContract
        .connect(croesus)
        .createLease(
          await trustIdContract.ids(croesus.address),
          await trustIdContract.ids(aurelius.address),
          '5',
          '12',
          croesusTokenAddress,
          3,
          'USD-SHI',
          getCurrentTimestamp(),
          anywherePlatformId,
          cid,
        )
      await createLeaseTx.wait()
      leaseIdCounter++
      // console.log('Lease created: ', await leaseContract.leases(2))

      //Validate token Lease
      const validateLeaseTx = await leaseContract
        .connect(aurelius)
        .validateLease(aureliusUserId, leaseIdCounter)
      await validateLeaseTx.wait()
      const lease = await leaseContract.leases(leaseIdCounter)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 12 rents
      // await oracleContract.updateRate('USD-ETH');
      const conversionRate = await oracleContract.getRate(lease.paymentData.currencyPair)
      console.log('Conversion rate: ', conversionRate[0].toNumber() / 10 ** 18) // usd-eth

      // $ * token dec/$
      const rentAmountInToken = lease.paymentData.rentAmount.mul(conversionRate[0])
      console.log('Rent amount in token: ', rentAmountInToken.toString())

      const totalAmountToApprove = rentAmountInToken.mul(12)
      await croesusToken
        .connect(aurelius)
        .approve(paymentManagerContract.address, totalAmountToApprove)

      for (let i = 0; i < 12; i++) {
        const payRentTx = await paymentManagerContract
          .connect(aurelius)
          .payFiatRentInToken(aureliusUserId, leaseIdCounter, i, true, rentAmountInToken)
        await payRentTx.wait()
        console.log('Aurelius paid rent: ', i)
      }

      const reviewLeaseTx = await leaseContract
        .connect(aurelius)
        .reviewLease(aureliusUserId, leaseIdCounter, 'TenantReviewURI')
      await reviewLeaseTx.wait()
      console.log('Aurelius reviewed lease: ', leaseIdCounter)
      const reviewLeaseTx2 = await leaseContract
        .connect(croesus)
        .reviewLease(croesusUserId, leaseIdCounter, 'OwnerReviewURI')
      await reviewLeaseTx2.wait()
      console.log('Croesus reviewed lease: ', leaseIdCounter)
    }

    if (fiatRentPaymentEth) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12)
      await croesusToken
        .connect(aurelius)
        .approve(paymentManagerContract.address, totalAmountToApprove)
      const auralusId = await trustIdContract.ids(aurelius.address)
      console.log('Aurelius id ', auralusId)

      //Create ETH lease
      const createLeaseTx = await leaseContract
        .connect(croesus)
        .createLease(
          await trustIdContract.ids(croesus.address),
          await trustIdContract.ids(aurelius.address),
          '5',
          '12',
          croesusTokenAddress,
          0,
          'USD-ETH',
          getCurrentTimestamp(),
          anywherePlatformId,
          cid,
        )
      await createLeaseTx.wait()
      leaseIdCounter++
      // console.log('Lease created: ', await leaseContract.leases(2))

      //Validate token Lease
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(aureliusUserId, 4)
      await validateLeaseTx.wait()
      const lease = await leaseContract.leases(leaseIdCounter)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 8 rents
      // await oracleContract.updateRate('USD-ETH');
      const conversionRate = await oracleContract.getRate(lease.paymentData.currencyPair)
      console.log('Conversion rate: ', conversionRate[0].toNumber()) // usd-eth * wei

      // $ * wei/$
      const rentAmountInWei = lease.paymentData.rentAmount.mul(conversionRate[0])
      console.log('Rent amount in token: ', rentAmountInWei.toString())

      for (let i = 0; i < 12; i++) {
        const payRentTx = await paymentManagerContract
          .connect(aurelius)
          .payFiatRentInEth(aureliusUserId, leaseIdCounter, i, true, { value: rentAmountInWei })
        await payRentTx.wait()
        console.log('Aurelius paid rent: ', i)
      }

      const reviewLeaseTx = await leaseContract
        .connect(aurelius)
        .reviewLease(aureliusUserId, leaseIdCounter, 'TenantReviewURI')
      await reviewLeaseTx.wait()
      console.log('Aurelius reviewed lease', leaseIdCounter)
      const reviewLeaseTx2 = await leaseContract
        .connect(croesus)
        .reviewLease(croesusUserId, leaseIdCounter, 'OwnerReviewURI')
      await reviewLeaseTx2.wait()
      console.log('Croesus reviewed lease', leaseIdCounter)
    }

    if (cancelLease) {
      //Maximus pays 4 rents
      for (let i = 0; i < 4; i++) {
        const payRentTx = await paymentManagerContract
          .connect(maximus)
          .payCryptoRent(maximusUserId, 1, i, true, {
            value: ethers.utils.parseEther('0.0000000000005'),
          })
        await payRentTx.wait()
      }

      //Maximus pays rent 7 with issues
      const payRentTx = await paymentManagerContract
        .connect(maximus)
        .payCryptoRent(maximusUserId, 1, 7, false, {
          value: ethers.utils.parseEther('0.0000000000005'),
        })
      await payRentTx.wait()
      const payments2 = await leaseContract.getPayments(1)
      console.log('Payments 7 paid: ', payments2[7])

      //Both cancel the lease
      const cancelTenantTx = await leaseContract.connect(maximus).cancelLease(maximusUserId, 1)
      await cancelTenantTx.wait()
      const cancelOwnerTx = await leaseContract.connect(croesus).cancelLease(croesusUserId, 1)
      await cancelOwnerTx.wait()
    }

    if (openLease) {
      //Create Open lease & proposal for crypto payment
      const createOpenLeaseTx = await leaseContract.connect(croesus).createOpenLease(
        // '4',
        croesusUserId,
        ethers.utils.parseEther('0.0000000000005'),
        ethers.constants.AddressZero,
        '12',
        'CRYPTO',
        getCurrentTimestamp(),
        anywherePlatformId,
        cid,
      )
      await createOpenLeaseTx.wait()
      leaseIdCounter++
      console.log('Open lease created: ', leaseIdCounter)

      //Maximus creates proposal for this lease
      const createProposalTx = await leaseContract
        .connect(maximus)
        .submitProposal(
          maximusUserId,
          leaseIdCounter,
          12,
          getCurrentTimestamp(),
          anywherePlatformId,
          'QmbyAESGfkKQb9sKRoFjTquA2pBKjA22nA8WsoiDPrfCm9',
        )
      await createProposalTx.wait()
      const proposal = await leaseContract.getProposal(leaseIdCounter, maximusUserId)
      console.log('Proposal created by Maximus for lease: ', proposal.ownerId)

      //Validate Proposal
      const validateLeaseTx = await leaseContract
        .connect(croesus)
        .validateProposal(croesusUserId, maximusUserId, leaseIdCounter)
      await validateLeaseTx.wait()
      const lease = await leaseContract.leases(leaseIdCounter)
      console.log('Proposal validated: ', lease.status)
      console.log('Lease updated: ', lease.status)

      //Maximus pays 8 rents
      for (let i = 0; i < 8; i++) {
        const payRentTx = await paymentManagerContract
          .connect(maximus)
          .payCryptoRent(maximusUserId, leaseIdCounter, i, true, {
            value: ethers.utils.parseEther('0.0000000000005'),
          })
        await payRentTx.wait()
        console.log('Maximus paid rent: ', i)
      }

      //Maximus pays 4 rents with issues
      for (let i = 8; i < 12; i++) {
        const payRentTx = await paymentManagerContract
          .connect(maximus)
          .payCryptoRent(maximusUserId, leaseIdCounter, i, false, {
            value: ethers.utils.parseEther('0.0000000000005'),
          })
        await payRentTx.wait()
        console.log('Maximus paid rent: ', i)
      }

      const reviewLeaseTx = await leaseContract
        .connect(maximus)
        .reviewLease(maximusUserId, leaseIdCounter, 'TenantReviewURI')
      await reviewLeaseTx.wait()
      console.log('Maximus reviewed lease: ', leaseIdCounter)
      const reviewLeaseTx2 = await leaseContract
        .connect(croesus)
        .reviewLease(croesusUserId, leaseIdCounter, 'OwnerReviewURI')
      await reviewLeaseTx2.wait()
      console.log('Croesus reviewed lease: ', leaseIdCounter)
    }

    console.log('*****************************************************************************')
    console.log('*****************************************************************************')
    console.log('*****************************************************************************')
    console.log('************************** All Data deployed ********************************')
    console.log('*****************************************************************************')
    console.log('*****************************************************************************')
    console.log('**                                                                         **')
    console.log('**               Please copy these addresses in:                           **')
    console.log('**                                                                         **')
    console.log('**               - sub-graph/networks.json                                 **')
    console.log('**               - sub-graph/subgraph.yaml                                 **')
    console.log('**                                                                         **')
    console.log('**               In the "src/sub-graph" directory                          **')
    console.log('**                                                                         **')
    console.log(`**   TrustId address: ${trustIdContract.address}           **`)
    console.log(`**   PlatformId address: ${platformIdContract.address}        **`)
    console.log(`**   LeaseId address: ${leaseContract.address}           **`)
    console.log(`**   PaymentManager address: ${paymentManagerContract.address}    **`)
    console.log('**                                                                         **')
    console.log('**                                                                         **')
    console.log('**                                                                         **')
    console.log('*****************************************************************************')
    console.log('*****************************************************************************')
    console.log('*****************************************************************************')

    // if (normalRent || cancelLease) {
    //   //Both review the lease
    //   const reviewLeaseTx = await leaseContract.connect(maximus).reviewLease(1, 'TenantReviewURI');
    //   await reviewLeaseTx.wait();
    //   const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(1, 'OwnerReviewURI');
    //   await reviewLeaseTx2.wait();
    // } else if (normalTokenRent) {
    //   //Both review the lease
    //   const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(2, 'TenantReviewURI');
    //   await reviewLeaseTx.wait();
    //   const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(2, 'OwnerReviewURI');
    //   await reviewLeaseTx2.wait();
    // }

    // const payments = await leaseContract.getPayments(2);
    // // console.log('Payments: ', payments);
    //
    // const leaseEnd = await leaseContract.leases(2)
    // // console.log('Lease end: ', leaseEnd)
    //
    // const hasLeaseEnd = await tenantIdContract.userHasLease(await tenantIdContract.ids(maximus.address));
    // console.log('Maximus has lease: ', hasLeaseEnd);
    //
    // const daveHasLeaseEnd = await tenantIdContract.userHasLease(await tenantIdContract.ids(aurelius.address));
    // console.log('Aurelius has lease: ', daveHasLeaseEnd);
  })
