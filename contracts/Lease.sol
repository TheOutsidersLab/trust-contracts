// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IexecRateOracle} from './IexecRateOracle.sol';
import {FakeIexecRateOracle} from './FakeIexecOracle.sol';
import {ERC721A} from "./libs/ERC721A.sol";
import {TrustId} from "./TrustId.sol";


/**
 * @title Lease
 * @notice This contracts allows owners to create Leases & tenants to pay their rent.
 * @author Quentin DC @ Starton Hackathon 2022
 */
//TODO add withdraw function
//TODO ownable for updatable slippage ?
//TODO Add require on payment type (enum ?)

contract Lease {
    // =========================== Enums & Structs =============================
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint64 public constant DIVIDER = 10**18;
    uint8 private slippage = 200; // per 10_000

    /**
     * @notice Enum for the status of the rent payments
     */
    enum PaymentStatus {
        PENDING,
        PAID,
        NOT_PAID,
        CANCELLED,
        CONFLICT
    }

    enum LeaseStatus {
        ACTIVE,
        PENDING,
        ENDED,
        CANCELLED
    }

    /**
     * @notice Struct for a lease with price
     * @param ownerId The id of the owner
     * @param tenantId The id of the tenant
     * @param paymentData The rent payment related data
     * @param totalNumberOfRents The amount of rent payments for the lease
     * @param reviewStatus Review-related data
     * @param rentPaymentInterval The minimum interval between each rent payment
     * @param rentPaymentLimitTime The minimum interval to mark a rent payment as not paid
     * @param startDate The start date of the lease
     * @param cancellation Lease cancellation related data
     * @param rentPayments Array of all the rent payments of the lease
     * @param metaData Metadata of the lease
     */
    struct Lease {
        uint256 ownerId;
        uint256 tenantId;
        PaymentData paymentData;
        uint8 totalNumberOfRents;
        ReviewStatus reviewStatus;
        uint256 rentPaymentInterval;
        uint256 rentPaymentLimitTime;
        uint256 startDate;
        Cancellation cancellation;
        LeaseStatus status;
        RentPayment[] rentPayments;
        string metaData;
    }

    /**
     * @notice Struct representing payment-related data
     * @param rentAmount Amount of the rent
     * @param paymentToken Token in which the rent will be paid
     * @param rentCurrency CRYPTO if rent is in crypto. Otherwise fiat currency available in list.
     */
    struct PaymentData {
        uint256 rentAmount;
        address paymentToken;
        string currencyPair;
    }

    /**
     * @notice Struct for "multisig" cancellation. When both params are true, all pending payments are cancelled and
     * the lease is ended
     * @param cancelledByOwner Owner cancellation signature
     * @param cancelledByTenant Tenant cancellation signature
     */
    struct Cancellation {
        bool cancelledByOwner;
        bool cancelledByTenant;
    }

    /**
     * @notice Struct representing review-related data
     * @param ownerReviewed True if Owner reviewed the ended lease
     * @param tenantReviewed True if Owner reviewed the ended lease
     * @param ownerReviewUri Tenant review IPFS URI
     * @param tenantReviewUri Owner review IPFS URI
     */
    struct ReviewStatus {
        bool ownerReviewed;
        bool tenantReviewed;
        string ownerReviewUri;
        string tenantReviewUri;
    }

    /**
     * @notice Struct for rent payments
     * @param validationDate The timestamp of the rent status update
     * @param withoutIssues True is the tenant had no issues with the rented property during this rent period
     * @param exchangeRate Exchange rate between the rent currency and the payment token | "0" if rent in token or ETH
     * @param exchangeRateTimestamp Timestamp of the exchange rate | "0" if rent in token or ETH
     * @param paymentStatus The status of the payment
     */
    struct RentPayment {
        uint256 validationDate;
        bool withoutIssues;
        int256 exchangeRate;
        uint256 exchangeRateTimestamp;
        PaymentStatus paymentStatus;
    }

    // =========================== Mappings ==============================

    /**
     * @notice Mapping of all leases
     */
    mapping(uint256 => Lease) public leases;

    //    string[] public availableCurrency = ['CRYPTO', 'USD', 'EUR'];

    TrustId trustIdContract;
    //    FakeIexecOracle rateOracle;
    IexecRateOracle rateOracle;


    constructor (address _trustIdContract, address _rateOracle) {
        _tokenIds.increment();
        trustIdContract = TrustId(_trustIdContract);
        //        rateOracle = FakeIexecOracle(_rateOracle);
        rateOracle = IexecRateOracle(_rateOracle);
    }

    // =========================== View functions ==============================

    /**
     * @notice Getter for all payments of a lease
     * @param _leaseId The id of the lease
     * @return rentPayments The array of all rent payments of the lease
     */
    function getPayments(uint256 _leaseId) external view returns(RentPayment[] memory rentPayments) {
        Lease storage lease = leases[_leaseId];
        return lease.rentPayments;
    }

    // =========================== User functions ==============================


    /**
     * @notice Function called by the owner to create a new lease
     * @param _tenantId The id of the tenant
     * @param _rentAmount The amount of the rent in fiat
     * @param _totalNumberOfRents The amount of rent payments for the lease
     * @param _paymentToken The address of the token used for payment
     * @param _rentPaymentInterval The minimum interval between each rent payment
     * @param _rentPaymentLimitTime The minimum interval to mark a rent payment as not paid
     * @param _currencyPair The currency pair used for rent price & payment | "CRYPTO" if rent in token or ETH
     * @param _startDate The start date of the lease
     */
    function createLease(
        uint256 _tenantId,
        uint256 _rentAmount,
        uint8 _totalNumberOfRents,
        address _paymentToken,
        uint256 _rentPaymentInterval,
        uint256 _rentPaymentLimitTime,
        string calldata _currencyPair,
        uint256 _startDate) external onlyTrustOwner
    {
        // Duplicate check
        //        require(trustIdContract.userIsOwner(msg.sender) == true, "Lease: You are not an owner");
        require(trustIdContract.getUser(_tenantId).id != 0, "Lease: Tenant does not exist");

        Lease storage lease = leases[_tokenIds.current()];
        lease.ownerId = trustIdContract.getUserId(msg.sender);
        lease.tenantId = _tenantId;
        lease.paymentData.rentAmount = _rentAmount;
        lease.totalNumberOfRents = _totalNumberOfRents;
        lease.paymentData.paymentToken = _paymentToken;
        lease.paymentData.currencyPair = _currencyPair;
        lease.rentPaymentInterval = _rentPaymentInterval;
        lease.rentPaymentLimitTime = _rentPaymentLimitTime;
        lease.startDate = _startDate;
        lease.status = LeaseStatus.PENDING;

        //Rent id starts at 0 as it will be the multiplicator for the Payment Intervals
        for(uint8 i = 0; i < lease.totalNumberOfRents; i++) {
            lease.rentPayments.push(RentPayment(0, false, 0, 0, PaymentStatus.PENDING));
        }

        emit LeaseCreated(_tokenIds.current(), _tenantId, lease.ownerId, _rentAmount, _totalNumberOfRents,
            _paymentToken, _rentPaymentInterval, _rentPaymentLimitTime, _startDate, _currencyPair);

        _tokenIds.increment();
    }

    /**
     * @notice Called by the tenant to update the lease metadata
     * @param _leaseId The id of the lease
     * @param _newCid The new IPFS URI of the lease metadata
     */
    function updateLeaseMetaData(uint256 _leaseId, string memory _newCid) external {
        Lease storage lease = leases[_leaseId];
        require(msg.sender == trustIdContract.ownerOf(lease.tenantId),
            "Only the tenant can call this function");
        require(bytes(_newCid).length > 0, "Should provide a valid IPFS URI");

        lease.metaData = _newCid;

        emit LeaseMetaDataUpdated(_leaseId, _newCid);
    }


    /**
     * @notice Called by the tenant or the owner to decline the lease proposition
     * @param _leaseId The id of the lease
     */
    function declineLease(uint256 _leaseId) external {
        Lease storage lease = leases[_leaseId];
        require(msg.sender == trustIdContract.ownerOf(lease.tenantId)
            || msg.sender == trustIdContract.ownerOf(lease.ownerId),
            "Only the tenant or Owner can call this function");

        lease.status = LeaseStatus.CANCELLED;

        emit UpdateLeaseStatus(_leaseId, LeaseStatus.CANCELLED);
    }


    /**
     * @notice Called by the tenant to validate the lease
     * @param _leaseId The id of the lease
     */
    function validateLease(uint256 _leaseId) external {
        Lease storage lease = leases[_leaseId];

        require(lease.ownerId != 0, "Lease does not exist");
        require(msg.sender == trustIdContract.ownerOf(lease.tenantId), "Only the tenant can call this function");
        require(lease.status == LeaseStatus.PENDING, "Lease was already validated");

        lease.status = LeaseStatus.ACTIVE;

        emit LeaseValidated(_leaseId);
    }

    // COMMENTED FOR NOW - STILL IN DISCUSSION
    //    /**
    //     * @notice Called by the tenant to set a rent payment from with to without issues
    //     * @param _leaseId The id of the lease
    //     * @param _rentId The id of the rent
    //     */
    //    function setRentPaymentToWithoutIssues(uint256 _leaseId, uint256 _rentId) external  {
    //        Lease storage lease = leases[_leaseId];
    //        RentPayment storage rentPayment = lease.rentPayments[_rentId];
    //        require(msg.sender == tenantContract.ownerOf(lease.tenantId),
    //            "Only the tenant can call this function");
    //        require(rentPayment.withoutIssues == true, "Status is already set to true");
    //        rentPayment.withoutIssues = false;
    //
    //        emit RentPaymentIssueStatusUpdated(_leaseId, _rentId, false);
    //    }

    /**
     * @notice Used to pay a rent using ETH
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     */
    function payCryptoRentInETH(uint256 _leaseId, uint256 _rentId, bool _withoutIssues) external payable {
        Lease storage lease = leases[_leaseId];

        //TODO Will be implemented when exchangeRate switched to an index
        //        require(lease.paymentData.exchangeRate == 'CRYPTO', "Lease: Rent is not set to crypto");
        address ownerAddress = trustIdContract.ownerOf(lease.tenantId);
        require(ownerAddress == msg.sender, "Only the tenant can perform this action");

        RentPayment storage rentPayment = lease.rentPayments[_rentId];

        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(block.timestamp >= lease.startDate + lease.rentPaymentInterval * _rentId, "Payment not due");
        require(rentPayment.paymentStatus == PaymentStatus.PENDING, "Payment is not pending, please contact the owner");

        require(msg.value == lease.paymentData.rentAmount, "Wrong rent value");

        payable (ownerAddress).transfer(msg.value);

        _mintFromTenant(_leaseId, _rentId, PaymentStatus.PAID, _withoutIssues);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit CryptoRentPaid(_leaseId, _rentId, _withoutIssues, msg.value);
    }

    /**
     * @notice Used to pay a rent in token using tokens
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @param _amount amount in tokens
     * @dev Only the registered tenant can call this function
     */
    function payCryptoRentInToken(uint256 _leaseId, uint256 _rentId, bool _withoutIssues, uint256 _amount) external {
        Lease storage lease = leases[_leaseId];
        //        require(lease.paymentData.exchangeRate == 'CRYPTO', "Lease: Rent is not set to crypto");

        require(trustIdContract.ownerOf(lease.tenantId) == msg.sender, "Only the tenant can perform this action");

        RentPayment storage rentPayment = lease.rentPayments[_rentId];

        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(block.timestamp >= lease.startDate + lease.rentPaymentInterval * _rentId, "Payment not due");
        require(rentPayment.paymentStatus == PaymentStatus.PENDING, "Payment is not pending, please contact the owner");

        IERC20 token = IERC20(lease.paymentData.paymentToken);

        require(token.balanceOf(msg.sender) >= _amount, "Not enough token balance");
        require(_amount >= lease.paymentData.rentAmount, "Wrong rent value");


        //Need allowance to Lease contract before executing this function
        token.transferFrom(msg.sender, trustIdContract.ownerOf(lease.ownerId), _amount);

        _mintFromTenant(_leaseId, _rentId, PaymentStatus.PAID, _withoutIssues);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit CryptoRentPaid(_leaseId, _rentId, _withoutIssues, _amount);
    }

    /**
     * @notice Used to pay a rent stated in Fiat currency using tokens
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @dev Only the registered tenant can call this function
     */
    function payFiatRentInEth(uint256 _leaseId, uint256 _rentId, bool _withoutIssues) external payable {
        Lease storage lease = leases[_leaseId];
        rateOracle.updateRate(lease.paymentData.currencyPair);

        //        require(lease.paymentData.exchangeRate != 'CRYPTO', "Lease: Rent is not set to fiat");
        address ownerAddress = trustIdContract.ownerOf(lease.tenantId);
        require(ownerAddress == msg.sender, "Only the tenant can perform this action");

        RentPayment storage rentPayment = lease.rentPayments[_rentId];

        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(block.timestamp >= lease.startDate + lease.rentPaymentInterval * _rentId, "Payment not due");
        require(rentPayment.paymentStatus == PaymentStatus.PENDING, "Payment is not pending, please contact the owner");


        (int256 exchangeRate, uint256 date) = rateOracle.getRate(lease.paymentData.currencyPair);
        rentPayment.exchangeRate = exchangeRate;
        rentPayment.exchangeRateTimestamp = date;

        // exchangeRate: in wei/Fiat | rentAmount in fiat currency
        uint256 rentAmountInWei = lease.paymentData.rentAmount * (uint256(exchangeRate));

        require(msg.value >= (rentAmountInWei - (rentAmountInWei * slippage) / 10000), "Wrong rent value");

        payable (ownerAddress).transfer(msg.value);

        _mintFromTenant(_leaseId, _rentId, PaymentStatus.PAID, _withoutIssues);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit FiatRentPaid(_leaseId, _rentId, _withoutIssues, msg.value, exchangeRate, date);
    }

    /**
     * @notice Used to pay a rent using tokens NOT IMPLEMENTED YET
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @param _amountInSmallestDecimal amount in smallest token decimal
     * @dev Only the registered tenant can call this function
     */
    function payFiatRentInToken(uint256 _leaseId, uint256 _rentId, bool _withoutIssues, uint256 _amountInSmallestDecimal) external {
        Lease storage lease = leases[_leaseId];
        rateOracle.updateRate(lease.paymentData.currencyPair);

        //        require(lease.paymentData.exchangeRate != 'CRYPTO', "Lease: Rent is not set to fiat");

        require(trustIdContract.ownerOf(lease.tenantId) == msg.sender, "Only the tenant can perform this action");

        RentPayment storage rentPayment = lease.rentPayments[_rentId];

        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(block.timestamp >= lease.startDate + lease.rentPaymentInterval * _rentId, "Payment not due");
        require(rentPayment.paymentStatus == PaymentStatus.PENDING, "Payment is not pending, please contact the owner");

        IERC20 token = IERC20(lease.paymentData.paymentToken);

        require(token.balanceOf(msg.sender) >= _amountInSmallestDecimal, "Not enough token balance");

        (int256 exchangeRate, uint256 date) = rateOracle.getRate(lease.paymentData.currencyPair);
        rentPayment.exchangeRate = exchangeRate;
        rentPayment.exchangeRateTimestamp = date;

        // exchangeRate: in tokenDecimal/Fiat | rentAmount in fiat currency
        uint256 rentAmountInToken = lease.paymentData.rentAmount * (uint256(exchangeRate));

        require(_amountInSmallestDecimal >= (rentAmountInToken - (rentAmountInToken * slippage) / 10000), "Wrong rent value");

        token.transferFrom(msg.sender, trustIdContract.ownerOf(lease.ownerId), _amountInSmallestDecimal);

        _mintFromTenant(_leaseId, _rentId, PaymentStatus.PAID, _withoutIssues);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit FiatRentPaid(_leaseId, _rentId, _withoutIssues, _amountInSmallestDecimal, exchangeRate, date);
    }

    /**
     * @notice Can be called by the owner to mark a rent as not paid after the rent payment limit time is reached
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @dev Only the owner of the lease can call this function
     */
    function markRentAsNotPaid(uint256 _leaseId, uint256 _rentId) external {
        Lease storage lease = leases[_leaseId];
        require(msg.sender == trustIdContract.ownerOf(lease.ownerId), "Only the owner can call this function");
        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(block.timestamp > lease.startDate + lease.rentPaymentLimitTime * _rentId, "Tenant still has time to pay");

        RentPayment storage rentPayment = lease.rentPayments[_rentId];

        require(rentPayment.paymentStatus == PaymentStatus.PENDING, "Payment already has another status");

        _mint(_leaseId, _rentId, PaymentStatus.NOT_PAID);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit RentNotPaid(_leaseId, _rentId);
    }

    /**
     * @notice Can be called by the owner to set a NOT_PAID rent back to PENDING, to give the tenant a possibility to pay his rent
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @dev Only the owner of the lease can call this function for a RentPayment set to NOT_PAID
     */
    function markRentAsPending(uint256 _leaseId, uint256 _rentId) external {
        Lease storage lease = leases[_leaseId];
        RentPayment storage rentPayment = lease.rentPayments[_rentId];
        require(msg.sender == trustIdContract.ownerOf(lease.ownerId), "Only the owner can call this function");
        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
        require(rentPayment.paymentStatus == PaymentStatus.NOT_PAID, "Payment must be set to NOT_PAID");

        _mint(_leaseId, _rentId, PaymentStatus.PENDING);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit SetRentToPending(_leaseId, _rentId);
    }

    /**
     * @notice Can be called by the owner or the tenant to cancel the remaining payments of a lease and make it as ended
     * @dev Both tenant and owner must call this function for the lease to be cancelled
     * @param _leaseId The id of the lease
     */
    function cancelLease(uint256 _leaseId) external {
        Lease storage lease = leases[_leaseId];
        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");

        if(msg.sender == trustIdContract.ownerOf(lease.ownerId)) {
            require(lease.cancellation.cancelledByOwner == false, "Lease already cancelled by owner");
            lease.cancellation.cancelledByOwner = true;
        } else if (msg.sender == trustIdContract.ownerOf(lease.tenantId)) {
            require(lease.cancellation.cancelledByTenant == false, "Lease already cancelled by tenant");
            lease.cancellation.cancelledByTenant = true;
        } else {
            revert("Only the owner or the tenant can call this function");
        }

        emit CancellationRequested(_leaseId, lease.cancellation.cancelledByOwner, lease.cancellation.cancelledByTenant);

        if(lease.cancellation.cancelledByOwner && lease.cancellation.cancelledByTenant) {
            for(uint8 i = 0; i < lease.totalNumberOfRents; i++) {
                RentPayment storage rentPayment = lease.rentPayments[i];
                if(rentPayment.paymentStatus == PaymentStatus.PENDING) {
                    _mint(_leaseId, i, PaymentStatus.CANCELLED);
                }
            }
            _updateLeaseAndPaymentsStatuses(_leaseId);
        }
    }

    /**
     * @notice Can be called by the owner or the tenant to review the lease after the lease had been terminated
     * @param _leaseId The id of the lease
     * @param _reviewUri The IPFS URI of the review
     * @dev Only one review per tenant / owner. Can be called again to update the review.
     */
    function reviewLease(uint256 _leaseId, string calldata _reviewUri) external {
        Lease storage lease = leases[_leaseId];
        require(lease.status == LeaseStatus.ENDED, "Lease: Lease is still not finished");
        if(msg.sender == trustIdContract.ownerOf(lease.tenantId)) {
            require(!lease.reviewStatus.tenantReviewed, "Lease: Tenant already reviewed");
            lease.reviewStatus.tenantReviewUri = _reviewUri;
            lease.reviewStatus.tenantReviewed = true;
            emit LeaseReviewedByTenant(_leaseId, _reviewUri);
        } else if(msg.sender == trustIdContract.ownerOf(lease.ownerId)) {
            require(!lease.reviewStatus.ownerReviewed, "Lease: Owner already reviewed");
            lease.reviewStatus.ownerReviewUri = _reviewUri;
            lease.reviewStatus.ownerReviewed = true;
            emit LeaseReviewedByOwner(_leaseId, _reviewUri);
        } else {
            revert("You are not allowed to review this lease");
        }
    }

    // =========================== Private functions ===========================

    /**
     * @notice Private function to update the payment status & potential issues of a rent payment
     * @param _leaseId The id of the lease
     * @param _rentId The rent payment id
     * @param _paymentStatus The new payment status
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     */
    function _mintFromTenant(uint256 _leaseId, uint256 _rentId, PaymentStatus _paymentStatus, bool _withoutIssues) private {
        RentPayment storage rentPayment = leases[_leaseId].rentPayments[_rentId];
        rentPayment.paymentStatus = _paymentStatus;
        rentPayment.withoutIssues = _withoutIssues;
        rentPayment.validationDate = block.timestamp;
    }

    /**
     * @notice Private function to update the payment status of a rent payment
     * @param _leaseId The id of the lease
     * @param _rentId The rent payment id
     * @param _paymentStatus The new payment status
     */
    function _mint(uint256 _leaseId, uint256 _rentId, PaymentStatus _paymentStatus) private {
        RentPayment storage rentPayment = leases[_leaseId].rentPayments[_rentId];
        rentPayment.paymentStatus = _paymentStatus;
        rentPayment.validationDate = block.timestamp;
    }

    /**
     * @notice Private function checking whether the lease is ended or not
     * @param _leaseId The id of the lease
     */
    function _updateLeaseAndPaymentsStatuses(uint256 _leaseId) private {
        Lease storage lease = leases[_leaseId];

        for(uint8 i = 0; i < lease.totalNumberOfRents; i++) {
            RentPayment storage rentPayment = lease.rentPayments[i];
            if(rentPayment.paymentStatus == PaymentStatus.PENDING ||
                rentPayment.paymentStatus == PaymentStatus.CONFLICT) {
                return;
            }
        }
        lease.status = LeaseStatus.ENDED;

        emit UpdateLeaseStatus(_leaseId, lease.status);
    }

    // =========================== Events ==============================

    event LeaseCreated(
        uint256 leaseId,
        uint256 tenantId,
        uint256 ownerId,
        uint256 rentAmount,
        uint8 totalNumberOfRents,
        address paymentToken,
        uint256 rentPaymentInterval,
        uint256 rentPaymentLimitTime,
        uint256 startDate,
        string currencyPair);

    event LeaseValidated(uint256 leaseId);

    event RentPaymentIssueStatusUpdated(uint256 leaseId, uint256 rentId, bool withoutIssues);

    event CryptoRentPaid(uint256 leaseId, uint256 rentId, bool withoutIssues, uint256 amount);

    event FiatRentPaid(uint256 leaseId, uint256 rentId, bool withoutIssues, uint256 amount, int256 exchangeRate, uint256 exchangeRateTimestamp);

    event RentNotPaid(uint256 leaseId, uint256 rentId);

    event SetRentToPending(uint256 leaseId, uint256 rentId);

    event UpdateLeaseStatus(uint256 leaseId, LeaseStatus status);

    event CancellationRequested(uint256 leaseId, bool cancelledByOwner, bool cancelledByTenant);

    event LeaseReviewedByOwner(uint256 leaseId, string reviewUri);

    event LeaseReviewedByTenant(uint256 leaseId, string reviewUri);

    event LeaseMetaDataUpdated(uint256 leaseId, string metaData);

    // =========================== Modifiers ==============================

    modifier onlyTrustOwner() {
        uint256 userId = trustIdContract.getUserId(msg.sender);
        require(trustIdContract.userIsOwner(userId) == true,
            "Only an owner can call this function");
        _;
    }

}
