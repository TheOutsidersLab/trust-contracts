import {task} from "hardhat/config";
import {ethers} from "hardhat";
import {getCurrentTimestamp} from "hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp";
import {ConfigAddresses} from "../contract-addresses";

//npx hardhat deploy --normal-rent --network localhost
//npx hardhat deploy --normal-token-rent --network localhost
//npx hardhat deploy --normal-token-rent --network localhost
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
    const [deployer, croseus, brutus, maximus, aurelius] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    await run("compile");


    //Deploy Oracle
    // const Oracle = await ethers.getContractFactory("IexecRateOracle");
    const Oracle = await ethers.getContractFactory("FakeIexecRateOracle");
    const oracleContract = await Oracle.deploy();
    console.log("Oracle address:", oracleContract.address);

    //Deploy OwnerId
    const OwnerId = await ethers.getContractFactory("OwnerId");
    const ownerIdContract = await OwnerId.deploy();
    console.log("OwnerId address:", ownerIdContract.address);

    //Deploy TenantId
    const TenantId = await ethers.getContractFactory("TenantId");
    const tenantIdContract = await TenantId.deploy();
    console.log("TenantId address:", tenantIdContract.address);

    //Deploy Lease
    const Lease = await ethers.getContractFactory("Lease");
    const leaseArgs: [string, string, string] = [ownerIdContract.address, tenantIdContract.address, oracleContract.address]
    const leaseContract = await Lease.deploy(...leaseArgs);
    console.log("Lease address:", leaseContract.address);

    //Add dependency to TenantId contract
    await tenantIdContract.updateLeaseContractAddress(leaseContract.address);

    //Deploy CRT token
    const CroesusToken = await ethers.getContractFactory("CroesusTokenERC20");
    const croesusToken = await CroesusToken.deploy();
    const croesusTokenAddress = croesusToken.address;
    console.log("CroesusToken address:", croesusTokenAddress);

    await croesusToken.transfer(brutus.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(maximus.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(aurelius.address, ethers.utils.parseEther('1000'))
    await croesusToken.transfer(croseus.address, ethers.utils.parseEther('1000'))

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

    // // Mint onwer & tenant ids
    const mintTxDeployerOwner = await ownerIdContract.connect(deployer).mint('TheBoss');
    await mintTxDeployerOwner.wait();
    console.log('TheBoss ownerId: ', await ownerIdContract.getOwnerIdFromAddress(deployer.address))

    const mintTxDeployerTenant = await tenantIdContract.connect(deployer).mint('TheBoss');
    await mintTxDeployerTenant.wait();
    console.log('TheBoss tenantId: ', await tenantIdContract.getUserId(deployer.address))

    const mintTx = await ownerIdContract.connect(croseus).mint('Croesus');
    await mintTx.wait();
    console.log('Croesus ownerId: ', await ownerIdContract.getOwnerIdFromAddress(croseus.address))

    const mintTx2 = await ownerIdContract.connect(brutus).mint('Brutus');
    await mintTx2.wait();
    console.log('Brutus ownerId: ', await ownerIdContract.getOwnerIdFromAddress(brutus.address))

    const mintTx3 = await tenantIdContract.connect(maximus).mint('Maximus');
    await mintTx3.wait();
    console.log('Maximus tenantId: ', await tenantIdContract.getUserId(maximus.address))

    const mintTx4 = await tenantIdContract.connect(aurelius).mint('Aurelius');
    await mintTx4.wait();
    console.log('Aurelius tenantId: ', await tenantIdContract.getUserId(aurelius.address));


    // console.log('Aurelius profil: ', await tenantIdContract.getTenant('2'));


    if (normalRent) {
      //Create lease for ETH payment
      const createLeaseTx = await leaseContract.connect(croseus).createLease(// '4',
        await tenantIdContract.getUserId(maximus.address),
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
      const validateLeaseTx = await leaseContract.connect(maximus).validateLease(1);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(1)
      console.log('Lease validated: ', lease.status)

      const hasLease = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
      console.log('Maximus has lease: ', hasLease);

      // //Reject Lease
      // const rejectLeaseTx = await leaseContract.connect(carol).declineLease(1);
      // await rejectLeaseTx.wait();
      // const lease = await leaseContract.leases(1)
      // console.log('Lease Declined: ', lease.status)
      //
      // const hasLease = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(carol.address));
      // console.log('Maximus has lease: ', hasLease);

      //Maximus pays 8 rents
      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(maximus).payCryptoRentInETH(1, i, true, {value: ethers.utils.parseEther('0.0000000000005')});
        await payRentTx.wait();
        console.log('Maximus paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croseus).markRentAsNotPaid(1, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(maximus).reviewLease(1, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Maximus reviewed lease: ', 1)
      const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(1, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 1)

      const hasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
      console.log('Maximus has lease: ', hasLeaseEnd);

      const daveHasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', daveHasLeaseEnd);
    }

    if (normalTokenRent) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);

      //Create token lease
      const createLeaseTx = await leaseContract.connect(croseus).createLease(// '4',
        await tenantIdContract.getUserId(aurelius.address),
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
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(2);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(1)
      console.log('Lease validated: ', lease.status)

      const hasLease = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', hasLease);

      //Aurelius pays 8 rents
      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(aurelius).payCryptoRentInToken(2, i, true, ethers.utils.parseEther('0.0000000000005'));
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croseus).markRentAsNotPaid(2, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(2, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease: ', 2)
      const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(2, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 2)

      const hasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
      console.log('Maximus has lease: ', hasLeaseEnd);

      const daveHasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', daveHasLeaseEnd);
    }


    if (fiatRentPaymentToken) {
      await oracleContract.updateRate('EUR-ETH');
      await oracleContract.updateRate('USD-ETH');
      await oracleContract.updateRate('USD-SHI');
      // const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      // await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);
      const aurelusId = await tenantIdContract.getUserId(aurelius.address)
      console.log('Aurelius id ', aurelusId)

      //Create token lease
      const createLeaseTx = await leaseContract.connect(croseus).createLease(
        await tenantIdContract.getUserId(aurelius.address),
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
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(3);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(3)
      console.log('Lease validated: ', lease.status)

      const hasLease = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', hasLease);

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
        const payRentTx = await leaseContract.connect(aurelius).payFiatRentInToken(3, i, true, rentAmountInToken);
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croseus).markRentAsNotPaid(3, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(3, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease: ', 3)
      const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(3, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease: ', 3)

      const hasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
      console.log('Maximus has lease: ', hasLeaseEnd);

      const daveHasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', daveHasLeaseEnd);
    }

    if (fiatRentPaymentEth) {
      const totalAmountToApprove = ethers.utils.parseEther('0.0000000000005').mul(12);
      await croesusToken.connect(aurelius).approve(leaseContract.address, totalAmountToApprove);
      const auralusId = await tenantIdContract.getUserId(aurelius.address)
      console.log('Aurelius id ', auralusId)

      //Create ETH lease
      const createLeaseTx = await leaseContract.connect(croseus).createLease(
        await tenantIdContract.getUserId(aurelius.address),
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
      const validateLeaseTx = await leaseContract.connect(aurelius).validateLease(4);
      await validateLeaseTx.wait();
      const lease = await leaseContract.leases(4)
      console.log('Lease validated: ', lease.status)

      const hasLease = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Aurelius has lease: ', hasLease);

      //Aurelius pays 8 rents
      // await oracleContract.updateRate('USD-ETH');
      const conversionRate = await oracleContract.getRate(lease.paymentData.currencyPair);
      console.log('Conversion rate: ', conversionRate[0].toNumber()); // usd-eth * wei

      // $ * wei/$
      const rentAmountInWei = lease.paymentData.rentAmount.mul(conversionRate[0]);
      console.log('Rent amount in token: ', rentAmountInWei.toString());

      for (let i = 0; i < 8; i++) {
        const payRentTx = await leaseContract.connect(aurelius).payFiatRentInEth(4, i, true, {value: rentAmountInWei});
        await payRentTx.wait();
        console.log('Aurelius paid rent: ', i)
      }

      //Croesus marks 4 rents as not paid
      for (let i = 8; i < 12; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croseus).markRentAsNotPaid(4, i);
        await markRentNotPaidTx.wait();
        console.log('Croesus marked rent as not paid: ', i)
      }

      const reviewLeaseTx = await leaseContract.connect(aurelius).reviewLease(4, 'TenantReviewURI');
      await reviewLeaseTx.wait();
      console.log('Aurelius reviewed lease', 4)
      const reviewLeaseTx2 = await leaseContract.connect(croseus).reviewLease(4, 'OwnerReviewURI');
      await reviewLeaseTx2.wait();
      console.log('Croesus reviewed lease', 4)

      const hasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
      console.log('Maximus has lease: ', hasLeaseEnd);

      const daveHasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
      console.log('Aurelius has lease: ', daveHasLeaseEnd);
    }

    if (cancelLease) {
      //Maximus pays 4 rents
      for (let i = 0; i < 4; i++) {
        const payRentTx = await leaseContract.connect(maximus).payCryptoRentInETH(1, i, true, {value: ethers.utils.parseEther('0.0000000000005')});
        await payRentTx.wait();
      }

      //Croesus marks 4 rents as not paid
      for (let i = 4; i < 8; i++) {
        const markRentNotPaidTx = await leaseContract.connect(croseus).markRentAsNotPaid(1, i);
        await markRentNotPaidTx.wait();
      }

      //Test owner marks rend 7 as pending
      const markRentPendingTx = await leaseContract.connect(croseus).markRentAsPending(1, 7);
      await markRentPendingTx.wait();

      const payments = await leaseContract.getPayments(1);
      console.log('Payments 7 pending: ', payments[7]);

      //A=Maximus pays rent 7 with issues
      const payRentTx = await leaseContract.connect(maximus).payCryptoRentInETH(1, 7, false, {value: ethers.utils.parseEther('0.0000000000005')});
      await payRentTx.wait();
      const payments2 = await leaseContract.getPayments(1);
      console.log('Payments 7 paid: ', payments2[7]);

      //Both cancel the lease
      const cancelTenantTx = await leaseContract.connect(maximus).cancelLease(1);
      await cancelTenantTx.wait();
      const cancelOwnerTx = await leaseContract.connect(croseus).cancelLease(1);
      await cancelOwnerTx.wait();
    }

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
    // const hasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(maximus.address));
    // console.log('Maximus has lease: ', hasLeaseEnd);
    //
    // const daveHasLeaseEnd = await tenantIdContract.tenantHasLease(await tenantIdContract.getUserId(aurelius.address));
    // console.log('Aurelius has lease: ', daveHasLeaseEnd);
  });