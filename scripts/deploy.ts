import {task} from "hardhat/config";
import {ethers} from "hardhat";
import {getCurrentTimestamp} from "hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp";

// npx hardhat deploy --fiat-rent-payment-eth --fiat-rent-payment-token --normal-rent --normal-token-rent --network localhost
task("deploy", "Deploys contracts")
  .addFlag('normalRent', 'Rents paid & not paid in ETH')
  .addFlag('alreadyDeployed', 'If contracts already deployed')
  .addFlag('normalTokenRent', 'Rents paid & not paid in token')
  .addFlag('fiatRentPaymentToken', 'Rents in fiat payment in token')
  .addFlag('fiatRentPaymentEth', 'Rents in fiat payment in token')
  .addFlag('cancelLease', 'Rents paid & not paid & lease is cancelled')
  .setAction(async (taskArgs, {ethers, run}) => {
    const {normalRent, normalTokenRent, cancelLease, fiatRentPaymentToken, fiatRentPaymentEth} = taskArgs;
    const [deployer, croesus, brutus, maximus, aurelius] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    await run("compile");


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
    const croesusToken = await CroesusToken.deploy();
    const croesusTokenAddress = croesusToken.address;
    console.log("CroesusToken address:", croesusTokenAddress);

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

    // Mint Userids & Give Owner Privileges

    const mintTxDeployerUser = await trustIdContract.connect(deployer).mint('TheBoss');
    await mintTxDeployerUser.wait();
    let deployerUserId = await trustIdContract.ids(deployer.address);
    console.log('TheBoss userId: ', deployerUserId)


    const mintTxCroesusUser = await trustIdContract.connect(croesus).mint('Croesus');
    await mintTxCroesusUser.wait();
    let croesusUserId = await trustIdContract.ids(croesus.address);
    console.log('Croesus userId: ',croesusUserId)


    const mintTxBrutusUser = await trustIdContract.connect(brutus).mint('Brutus');
    await mintTxBrutusUser.wait();
    let brutusUserId = await trustIdContract.ids(brutus.address);
    console.log('Brutus userId: ', brutusUserId)


    const mintTxMaximusUser = await trustIdContract.connect(maximus).mint('Maximus');
    await mintTxMaximusUser.wait();
    let maximusUserId = await trustIdContract.ids(maximus.address);
    console.log('Maximus userId: ',maximusUserId)


    const mintTxAureliusUser = await trustIdContract.connect(aurelius).mint('Aurelius');
    await mintTxAureliusUser.wait();
    let aureliusUserId = await trustIdContract.ids(aurelius.address);
    console.log('Aurelius userId: ', aureliusUserId)


    // console.log('Aurelius profil: ', await tenantIdContract.getTenant('2'));


    if (normalRent) {
      //Create lease for ETH payment
      const createLeaseTx = await leaseContract.connect(croesus).createLease(// '4',
        await trustIdContract.ids(croesus.address),
        await trustIdContract.ids(maximus.address),
        ethers.utils.parseEther('0.0000000000005'),
        '12',
        ethers.constants.AddressZero,
        1,
        1,
        'CRYPTO',
        getCurrentTimestamp(),);
      await createLeaseTx.wait();
      // console.log('Lease created: ', await leaseContract.leases(1))

      //Validate Lease
      const validateLeaseTx = await leaseContract.connect(maximus).validateLease(maximusUserId,1);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(1)
      console.log('Lease validated: ', lease.status)

      // //Reject Lease
      // const rejectLeaseTx = await leaseContract.connect(carol).declineLease(1);
      // await rejectLeaseTx.wait();
      // const lease = await leaseContract.leases(1)
      // console.log('Lease Declined: ', lease.status)
      //
      // const hasLease = await tenantIdContract.userHasLease(await tenantIdContract.ids(carol.address));
      // console.log('Maximus has lease: ', hasLease);

      //Maximus pays 8 rents
      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(maximus).payCryptoRent(maximusUserId,1, i, true, {value: ethers.utils.parseEther('0.0000000000005')});
        await payRentTx.wait();
        console.log('Maximus paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croesus).markRentAsNotPaid(croesusUserId,1, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(maximus).reviewLease(maximusUserId,1, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Maximus reviewed lease: ', 1)
      const reviewLeaseTx2 = await leaseContract.connect(croesus).reviewLease(croesusUserId,1, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 1)
    }

    if (normalTokenRent) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);

      //Create token lease
      const createLeaseTx = await leaseContract.connect(croesus).createLease(// '4',
        await trustIdContract.ids(croesus.address),
        await trustIdContract.ids(aurelius.address),
        ethers.utils.parseEther('0.0000000000005'),
        '12',
        croesusTokenAddress,
        2,
        2,
        'CRYPTO',
        getCurrentTimestamp(),);
      await createLeaseTx.wait();
      // console.log('Lease created: ', await leaseContract.leases(2))

      //Validate token Lease
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(aureliusUserId,2);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(1)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 8 rents
      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(aurelius).payCryptoRent(aureliusUserId,2, i, true);
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croesus).markRentAsNotPaid(croesusUserId,2, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(aureliusUserId,2, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease: ', 2)
      const reviewLeaseTx2 = await leaseContract.connect(croesus).reviewLease(croesusUserId,2, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 2)
    }


    if (fiatRentPaymentToken) {
      await oracleContract.updateRate('EUR-ETH');
      await oracleContract.updateRate('USD-ETH');
      await oracleContract.updateRate('USD-SHI');
      // const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      // await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);
      const aureliusId = await trustIdContract.ids(aurelius.address)
      console.log('Aurelius id ', aureliusId)

      //Create token lease
      const createLeaseTx = await leaseContract.connect(croesus).createLease(
        await trustIdContract.ids(croesus.address),
        await trustIdContract.ids(aurelius.address),
        "5",
        '12',
        croesusTokenAddress,
        2,
        3,
        'USD-SHI',
        getCurrentTimestamp(),);
      await createLeaseTx.wait();
      // console.log('Lease created: ', await leaseContract.leases(2))

      //Validate token Lease
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(aureliusUserId,3);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(3)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 8 rents
      // await oracleContract.updateRate('USD-ETH');
      const conversionRate = await oracleContract.getRate(lease.paymentData.currencyPair);
      console.log('Conversion rate: ', conversionRate[0].toNumber() / 10**18); // usd-eth

      // $ * token dec/$
      const rentAmountInToken = lease.paymentData.rentAmount.mul(conversionRate[0]);
      console.log('Rent amount in token: ', rentAmountInToken.toString());

      const totalAmountToApprove = rentAmountInToken.mul(8);
      await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);

      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(aurelius).payFiatRentInToken(aureliusUserId,3, i, true, rentAmountInToken);
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croesus).markRentAsNotPaid(croesusUserId,3, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(aureliusUserId,3, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease: ', 3)
      const reviewLeaseTx2 = await leaseContract.connect(croesus).reviewLease(croesusUserId,3, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 3)

    }

    if (fiatRentPaymentEth) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);
      const auralusId = await trustIdContract.ids(aurelius.address)
      console.log('Aurelius id ', auralusId)

      //Create ETH lease
      const createLeaseTx = await leaseContract.connect(croesus).createLease(
        await trustIdContract.ids(croesus.address),
        await trustIdContract.ids(aurelius.address),
        "5",
        '12',
        croesusTokenAddress,
        0,
        0,
        'USD-ETH',
        getCurrentTimestamp(),);
      await createLeaseTx.wait();
      // console.log('Lease created: ', await leaseContract.leases(2))

      //Validate token Lease
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(aureliusUserId,4);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(4)
      console.log('Lease validated: ', lease.status)

      //Aurelius pays 8 rents
      // await oracleContract.updateRate('USD-ETH');
      const conversionRate = await oracleContract.getRate(lease.paymentData.currencyPair);
      console.log('Conversion rate: ', conversionRate[0].toNumber()); // usd-eth * wei

      // $ * wei/$
      const rentAmountInWei = lease.paymentData.rentAmount.mul(conversionRate[0]);
      console.log('Rent amount in token: ', rentAmountInWei.toString());

      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(aurelius).payFiatRentInEth(aureliusUserId,4, i, true, {value: rentAmountInWei});
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croesus).markRentAsNotPaid(croesusUserId,4, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(aureliusUserId,4, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease', 4)
      const reviewLeaseTx2 = await leaseContract.connect(croesus).reviewLease(croesusUserId,4, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease', 4)
    }

    if (cancelLease) {
      //Maximus pays 4 rents
      for (let i = 0; i < 4; i++) {
        const payRentTx = await leaseContract.connect(maximus).payCryptoRent(maximusUserId,1, i, true, {value: ethers.utils.parseEther('0.0000000000005')});
        await payRentTx.wait();
      }

      //Croesus marks 4 rents as not paid
      for (let i = 4; i < 8; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croesus).markRentAsNotPaid(croesusUserId,1, i);
        await markRentNotPaidTx.wait();
      }

      //Test owner marks rend 7 as pending
      const markRentPendingTx = await leaseContract.connect(croesus).markRentAsPending(croesusUserId,1, 7);
      await markRentPendingTx.wait();

      const payments = await leaseContract.getPayments(1);
      console.log('Payments 7 pending: ', payments[7]);

      //A=Maximus pays rent 7 with issues
      const payRentTx = await leaseContract.connect(maximus).payCryptoRent(maximusUserId,1, 7, false, {value: ethers.utils.parseEther('0.0000000000005')});
      await payRentTx.wait();
      const payments2 = await leaseContract.getPayments(1);
      console.log('Payments 7 paid: ', payments2[7]);

      //Both cancel the lease
      const cancelTenantTx = await leaseContract.connect(maximus).cancelLease(maximusUserId,1);
      await cancelTenantTx.wait();
      const cancelOwnerTx = await leaseContract.connect(croesus).cancelLease(croesusUserId,1);
      await cancelOwnerTx.wait();
    }

    console.log('***********************************************************************')
    console.log('***********************************************************************')
    console.log('***********************************************************************')
    console.log('************************** All Data deployed **************************')
    console.log('***********************************************************************')
    console.log('***********************************************************************')
    console.log('**                                                                   **')
    console.log('**               Please copy these addresses in:                     **')
    console.log('**                                                                   **')
    console.log('**               - sub-graph/networks.json                           **')
    console.log('**               - sub-graph/subgraph.yaml                           **')
    console.log('**                                                                   **')
    console.log('**               In the "src/sub-graph" directory                    **')
    console.log('**                                                                   **')
    console.log(`**   TrustId address:, ${trustIdContract.address}    **`)
    console.log(`**   LeaseId address:, ${leaseContract.address}    **`)
    console.log('**                                                                   **')
    console.log('**                                                                   **')
    console.log('**                                                                   **')
    console.log('***********************************************************************')
    console.log('***********************************************************************')
    console.log('***********************************************************************')



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
  });
