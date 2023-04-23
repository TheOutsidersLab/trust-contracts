// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IexecRateOracle} from "./IexecRateOracle.sol";
import {FakeIexecRateOracle} from "./FakeIexecOracle.sol";
import {TrustId} from "./TrustId.sol";
import {PlatformId} from "./PlatformId.sol";
import {ILease} from "./interfaces/ILease.sol";

/**
 * @title PaymentManager
 * @notice This contracts owns all the functions used for payments
 * @author Quentin DC
 */
contract PaymentManager is AccessControl {
    // =========================== Declarations =============================

    /**
     * @notice The fee tolerates slippage percentage for fiat-based payments
     */
    uint8 private slippage = 200; // per 10_000

    /**
     * @notice The fee divider used for every fee rates
     */
    uint16 private constant FEE_DIVIDER = 10000;

    /**
     * @notice Instance of TrustId.sol contract
     */
    TrustId trustIdContract;
    //    FakeIexecOracle rateOracle;

    /**
     * @notice Instance of IexecRateOracle.sol contract
     */
    IexecRateOracle rateOracle;

    /**
     * @notice Instance of PlatformId.sol contract
     */
    PlatformId platformIdContract;

    /**
     * @notice Instance of Lease.sol contract
     */
    ILease leaseContract;

    /**
     * @notice (Upgradable) Wallet which will receive the protocol fees
     */
    address payable public protocolWallet;

    /**
     * @notice Percentage paid to the protocol (per 10,000, upgradable)
     */
    uint16 public protocolFeeRate;

    constructor(address _trustIdContract, address _rateOracle, address _platformIdContract, address _leaseContract){
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        trustIdContract = TrustId(_trustIdContract);
        //        rateOracle = FakeIexecOracle(_rateOracle);
        rateOracle = IexecRateOracle(_rateOracle);
        platformIdContract = PlatformId(_platformIdContract);
        leaseContract = ILease(_leaseContract);
        updateProtocolFeeRate(100);
    }

    // =========================== Owner functions ==============================

    /**
     * @notice Updates the Protocol Fee rate
     * @dev Only the owner can call this function
     * @param _protocolFeeRate The new protocol fee
     */
    function updateProtocolFeeRate(uint16 _protocolFeeRate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolFeeRate = _protocolFeeRate;
        emit ProtocolFeeRateUpdated(_protocolFeeRate);
    }

    /**
     * @notice Updates the Protocol wallet that receive fees
     * @dev Only the owner can call this function
     * @param _protocolWallet The new wallet address
     */
    function updateProtocolWallet(address payable _protocolWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolWallet = _protocolWallet;
    }

    // =========================== User functions ==============================

    /**
     * @notice Used to pay a rent using ETH
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     */
    function payCryptoRent(
        uint256 _profileId,
        uint256 _leaseId,
        uint256 _rentId,
        bool _withoutIssues
    ) external payable {
        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
        leaseContract.isValid(_leaseId);
        ILease.Lease memory lease = leaseContract.getLease(_leaseId);
        require(_profileId == lease.tenantId, "Lease: Only the tenant can call this function");
        require(lease.status == ILease.LeaseStatus.ACTIVE, "Lease is not Active");

        ILease.TransactionPayment memory rentPayment = lease.rentPayments[_rentId];

        require(
            rentPayment.paymentStatus != ILease.PaymentStatus.PAID ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CANCELLED ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CONFLICT,
            "Payment is not pending"
        );

        if (lease.paymentData.paymentToken == address(0)) {
            require(msg.value == lease.paymentData.rentAmount, "Non-matching funds");
        } else {
            require(msg.value == 0, "Non-matching funds");
        }

        // Calculate Lease & Protocol fees
        uint16 leaseFee = platformIdContract.getOriginLeaseFeeRate(lease.platformId);
        uint256 leaseFeeAmount = (lease.paymentData.rentAmount * leaseFee) / FEE_DIVIDER;
        uint256 protocolFeeAmount = (lease.paymentData.rentAmount * protocolFeeRate) / FEE_DIVIDER;

        // Pay rent to owner & platform & protocol fees
        if (address(0) == lease.paymentData.paymentToken) {
            trustIdContract.ownerOf(lease.ownerId).call{value: msg.value - (leaseFeeAmount + protocolFeeAmount)}("");
            protocolWallet.call{value: protocolFeeAmount}("");
            platformIdContract.ownerOf(lease.platformId).call{value: leaseFeeAmount}("");
        } else {
            IERC20(lease.paymentData.paymentToken).transferFrom(
                msg.sender,
                trustIdContract.ownerOf(lease.ownerId),
                lease.paymentData.rentAmount - (leaseFeeAmount + protocolFeeAmount)
            );
            IERC20(lease.paymentData.paymentToken).transferFrom(msg.sender, protocolWallet, (protocolFeeAmount));
            IERC20(lease.paymentData.paymentToken).transferFrom(
                msg.sender,
                payable(platformIdContract.ownerOf(lease.platformId)),
                (leaseFeeAmount)
            );
        }

        leaseContract.validateRentPayment(_leaseId, _rentId, _withoutIssues);

        emit CryptoRentPaid(_leaseId, _rentId, _withoutIssues, msg.value);
    }

    /**
     * @notice Used to pay a rent stated in Fiat currency using tokens
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @dev Only the registered tenant can call this function
     */
    function payFiatRentInEth(
        uint256 _profileId,
        uint256 _leaseId,
        uint256 _rentId,
        bool _withoutIssues
    ) external payable {
        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
        leaseContract.isValid(_leaseId);
        ILease.Lease memory lease = leaseContract.getLease(_leaseId);
        require(_profileId == lease.tenantId, "Lease: Only the tenant can call this function");
        require(lease.status == ILease.LeaseStatus.ACTIVE, "Lease is not Active");

        ILease.TransactionPayment memory rentPayment = lease.rentPayments[_rentId];

        require(
            rentPayment.paymentStatus != ILease.PaymentStatus.PAID ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CANCELLED ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CONFLICT,
            "Payment is not pending"
        );

        (int256 exchangeRate, uint256 date) = rateOracle.getRate(lease.paymentData.currencyPair);
        rentPayment.exchangeRate = exchangeRate;
        rentPayment.exchangeRateTimestamp = date;

        // exchangeRate: in wei/Fiat | rentAmount in fiat currency
        uint256 rentAmountInWei = lease.paymentData.rentAmount * (uint256(exchangeRate));

        require(msg.value >= (rentAmountInWei - (rentAmountInWei * slippage) / FEE_DIVIDER), "Wrong rent value");
        require(msg.value <= (rentAmountInWei + (rentAmountInWei * slippage) / FEE_DIVIDER), "Wrong rent value");

        // Calculate Lease & Protocol fees
        uint16 leaseFee = platformIdContract.getOriginLeaseFeeRate(lease.platformId);
        uint256 leaseFeeAmount = (rentAmountInWei * leaseFee) / FEE_DIVIDER;
        uint256 protocolFeeAmount = (rentAmountInWei * protocolFeeRate) / FEE_DIVIDER;

        // Pay rent to owner & platform & protocol fees
        trustIdContract.ownerOf(lease.ownerId).call{value: msg.value - (leaseFeeAmount + protocolFeeAmount)}("");
        protocolWallet.call{value: protocolFeeAmount}("");
        platformIdContract.ownerOf(lease.platformId).call{value: leaseFeeAmount}("");

        leaseContract.validateRentPayment(_leaseId, _rentId, _withoutIssues);

        emit FiatRentPaid(_leaseId, _rentId, _withoutIssues, msg.value, exchangeRate, date);
    }

    /**
     * @notice Used to pay a rent using tokens NOT IMPLEMENTED YET
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @param _amountInSmallestDecimal amount in smallest token decimal
     * @dev Only the registered tenant can call this function
     */
    function payFiatRentInToken(
        uint256 _profileId,
        uint256 _leaseId,
        uint256 _rentId,
        bool _withoutIssues,
        uint256 _amountInSmallestDecimal
    ) external {
        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
        leaseContract.isValid(_leaseId);
        ILease.Lease memory lease = leaseContract.getLease(_leaseId);
        require(_profileId == lease.tenantId, "Lease: Only the tenant can call this function");
        require(lease.status == ILease.LeaseStatus.ACTIVE, "Lease is not Active");

        //TODO Will be implemented when exchangeRate switched to an index
        //        require(lease.paymentData.exchangeRate == 'CRYPTO', "Lease: Rent is not set to crypto");

        ILease.TransactionPayment memory rentPayment = lease.rentPayments[_rentId];

        require(
            rentPayment.paymentStatus != ILease.PaymentStatus.PAID ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CANCELLED ||
            rentPayment.paymentStatus != ILease.PaymentStatus.CONFLICT,
            "Payment is not pending"
        );

        IERC20 token = IERC20(lease.paymentData.paymentToken);

        require(token.balanceOf(msg.sender) >= _amountInSmallestDecimal, "Not enough token balance");

        (int256 exchangeRate, uint256 date) = rateOracle.getRate(lease.paymentData.currencyPair);
        rentPayment.exchangeRate = exchangeRate;
        rentPayment.exchangeRateTimestamp = date;

        // exchangeRate: in tokenDecimal/Fiat | rentAmount in fiat currency
        uint256 rentAmountInToken = lease.paymentData.rentAmount * (uint256(exchangeRate));

        require(
            _amountInSmallestDecimal >= (rentAmountInToken - (rentAmountInToken * slippage) / FEE_DIVIDER),
            "Wrong rent value"
        );
        require(
            _amountInSmallestDecimal <= (rentAmountInToken + (rentAmountInToken * slippage) / FEE_DIVIDER),
            "Wrong rent value"
        );

        // Calculate Lease & Protocol fees
        uint16 leaseFee = platformIdContract.getOriginLeaseFeeRate(lease.platformId);
        uint256 leaseFeeAmount = (rentAmountInToken * leaseFee) / FEE_DIVIDER;
        uint256 protocolFeeAmount = (rentAmountInToken * protocolFeeRate) / FEE_DIVIDER;

        token.transferFrom(
            msg.sender,
            trustIdContract.ownerOf(lease.ownerId),
            _amountInSmallestDecimal - (leaseFeeAmount + protocolFeeAmount)
        );
        token.transferFrom(msg.sender, protocolWallet, (protocolFeeAmount));
        token.transferFrom(msg.sender, payable(platformIdContract.ownerOf(lease.platformId)), (leaseFeeAmount));

        leaseContract.validateRentPayment(_leaseId, _rentId, _withoutIssues);

        emit FiatRentPaid(_leaseId, _rentId, _withoutIssues, _amountInSmallestDecimal, exchangeRate, date);
    }

    // =============================== Events ==================================

    event CryptoRentPaid(uint256 leaseId, uint256 rentId, bool withoutIssues, uint256 amount);

    event FiatRentPaid(
        uint256 leaseId,
        uint256 rentId,
        bool withoutIssues,
        uint256 amount,
        int256 exchangeRate,
        uint256 exchangeRateTimestamp
    );

    /**
     * @notice Emitted after the protocol fee was updated
     * @param _protocolFeeRate The new protocol fee
     */
    event ProtocolFeeRateUpdated(uint16 _protocolFeeRate);
}
