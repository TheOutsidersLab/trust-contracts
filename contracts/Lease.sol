// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TrustId} from "./TrustId.sol";
import {PlatformId} from "./PlatformId.sol";

/**
 * @title Lease
 * @notice This contracts allows owners to create Leases & tenants to pay their rent.
 * @author Quentin DC
 */
//TODO add withdraw function
//TODO ownable for updatable slippage ?
//TODO Add require on payment type (enum ?)

contract Lease is AccessControl {
    // =========================== Enums & Structs =============================
    using Counters for Counters.Counter;
    Counters.Counter private _leaseIds;
    Counters.Counter private _openProposalIds;

    /**
     * @notice The fee tolerates slippage percentage for fiat-based payments
     */
    uint8 private slippage = 200; // per 10_000

    /**
     * @notice The fee divider used for every fee rates
     */
    uint16 private constant FEE_DIVIDER = 10000;

    /**
     * @notice Role granting Payment Manager permission
     */
    bytes32 public constant PAYMENT_MANAGER_ROLE = keccak256("PAYMENT_MANAGER_ROLE");

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

    enum ProposalStatus {
        PENDING,
        ACCEPTED,
        REJECTED
    }

    /**
     * @notice Struct for a lease with price
     * @param ownerId The id of the owner
     * @param tenantId The id of the tenant
     * @param paymentData The rent payment related data
     * @param totalNumberOfRents The amount of rent payments for the lease
     * @param reviewStatus Review-related data
     * @param rentPaymentInterval The minimum interval between each rent payment
     * @param startDate The start date of the lease
     * @param cancellation Lease cancellation related data
     * @param rentPayments Array of all the rent payments of the lease
     * @param metaData Metadata of the lease
     * @param platformId The id of the platform on which the Lease was created
     * @param proposalId In case of an Open Lease or Open Proposal, the id of the proposal linked to the lease. 0 if no proposal.
     */
    struct Lease {
        uint256 ownerId;
        uint256 tenantId;
        uint8 totalNumberOfRents;
        uint256 rentPaymentInterval;
        uint256 startDate;
        string metaData;
        PaymentData paymentData;
        ReviewStatus reviewStatus;
        Cancellation cancellation;
        LeaseStatus status;
        TransactionPayment[] rentPayments;
        uint256 platformId;
        uint256 proposalId;
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
     * @notice Struct for cancellation. When both params are true, all pending payments are cancelled and
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
     * @notice Struct for a proposal
     * @param ownerId The id of the profile
     * @param totalNumberOfRents The amount of rent payments for the lease
     * @param startDate The start date of the lease
     * @param platformId The id of the platform on which the Proposal was created
     * @param metaData Metadata of the proposal
     */
    struct Proposal {
        uint256 ownerId;
        uint8 totalNumberOfRents;
        uint256 startDate;
        uint256 platformId;
        string metaData;
    }

    /**
     * @notice Struct for a proposal
     * @param ownerId The id of the proposal owner
     * @param status The status of the proposal
     * @param platformId The id of the platform on which the Proposal was created
     * @param cid The IPFS cid of the proposal's metadata
     */
    struct OpenProposal {
        uint256 ownerId;
        ProposalStatus status;
        uint256 platformId;
        string cid;
    }

    /**
     * @notice Struct for Transaction payments
     * @param validationDate The timestamp of the transaction status update
     * @param withoutIssues True is the tenant had no issues with the rented property during this rent period
     * @param exchangeRate Exchange rate between the rent currency and the payment token | "0" if rent in token or ETH
     * @param exchangeRateTimestamp Timestamp of the exchange rate | "0" if rent in token or ETH
     * @param paymentStatus The status of the payment
     */
    struct TransactionPayment {
        uint256 validationDate;
        bool withoutIssues;
        int256 exchangeRate;
        uint256 exchangeRateTimestamp;
        PaymentStatus paymentStatus;
    }

    // =========================== Declarations ==============================

    /**
     * @notice Mapping of all leases
     */
    mapping(uint256 => Lease) public leases;

    /**
     * @notice Applications mappings index by lease ID and owner ID
     */
    mapping(uint256 => mapping(uint256 => Proposal)) public proposals;

    /**
     * @notice Open Proposals mappings index by openProposal ID
     */
    mapping(uint256 => OpenProposal) public openProposals;

    //    string[] public availableCurrency = ['CRYPTO', 'USD', 'EUR'];

    /**
     * @notice Instance of TrustId.sol contract
     */
    TrustId trustIdContract;

    /**
     * @notice Instance of PlatformId.sol contract
     */
    PlatformId platformIdContract;

    /**
     * @notice (Upgradable) Wallet which will receive the protocol fees
     */
    address payable public protocolWallet;

    /**
     * @notice Percentage paid to the protocol (per 10,000, upgradable)
     */
    uint16 public protocolFeeRate;

    constructor(address _trustIdContract, address _platformIdContract) {
        _leaseIds.increment();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        trustIdContract = TrustId(_trustIdContract);
        platformIdContract = PlatformId(_platformIdContract);
        updateProtocolFeeRate(100);
    }

    // =========================== View functions ==============================

    /**
     * @notice Getter for all payments of a lease
     * @param _leaseId The id of the lease
     * @return rentPayments The array of all rent payments of the lease
     */
    function getPayments(uint256 _leaseId) external view returns (TransactionPayment[] memory rentPayments) {
        Lease storage lease = leases[_leaseId];
        return lease.rentPayments;
    }

    /**
     * @notice Getter for a proposal
     * @param _leaseId The id of the lease
     * @param _ownerId The id of the proposal's owner
     * @return proposal The proposal
     */
    function getProposal(uint256 _leaseId, uint256 _ownerId) external view returns (Proposal memory proposal) {
        return proposals[_leaseId][_ownerId];
    }

    /**
     * @notice Getter for a lease
     * @param _leaseId The id of the lease
     * @return lease The Lease
     */
    function getLease(uint256 _leaseId) external view returns (Lease memory lease) {
        return leases[_leaseId];
    }

    /**
     * @notice Check whether the Lease Id is valid.
     * @param _leaseId The Lease Id.
     */
    function isValid(uint256 _leaseId) public view {
        require(_leaseId > 0 && _leaseId <= _leaseIds.current(), "Invalid lease ID");
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
     * @notice Function called by the owner to create a new lease assigned to a tenant
     * @param _ownerId The id of the owner
     * @param _tenantId The id of the tenant
     * @param _rentAmount The amount of the rent in fiat
     * @param _totalNumberOfRents The amount of rent payments for the lease
     * @param _paymentToken The address of the token used for payment
     * @param _rentPaymentInterval The minimum interval between each rent payment
     * @param _currencyPair The currency pair used for rent price & payment | "CRYPTO" if rent in token or ETH
     * @param _startDate The start date of the lease
     */
    //TODO consider removing "_ownerId" if ever signature is implemented
    function createLease(
        uint256 _ownerId,
        uint256 _tenantId,
        uint256 _rentAmount,
        uint8 _totalNumberOfRents,
        address _paymentToken,
        uint256 _rentPaymentInterval,
        string calldata _currencyPair,
        uint256 _startDate,
        uint256 _platformId
    ) external onlyTrustOwner(_ownerId) returns (uint256 leaseId) {
        Lease storage lease = leases[_leaseIds.current()];
        lease.ownerId = _ownerId;
        lease.tenantId = _tenantId;
        lease.paymentData.rentAmount = _rentAmount;
        lease.totalNumberOfRents = _totalNumberOfRents;
        lease.paymentData.paymentToken = _paymentToken;
        lease.paymentData.currencyPair = _currencyPair;
        lease.rentPaymentInterval = _rentPaymentInterval;
        lease.startDate = _startDate;
        lease.status = LeaseStatus.PENDING;
        lease.platformId = _platformId;

        //Rent id starts at 0 as it will be the multiplicator for the Payment Intervals
        for (uint8 i = 0; i < lease.totalNumberOfRents; i++) {
            lease.rentPayments.push(TransactionPayment(0, false, 0, 0, PaymentStatus.PENDING));
        }

        emit LeaseCreated(
            _leaseIds.current(),
            _tenantId,
            lease.ownerId,
            _totalNumberOfRents,
            _startDate,
            _rentPaymentInterval,
            _platformId
            //            "cid"
        );

        emit LeasePaymentDataUpdated(_leaseIds.current(), _rentAmount, _paymentToken, _currencyPair);

        uint256 leaseId = _leaseIds.current();
        _leaseIds.increment();

        return leaseId;
    }

    /**
     * @notice Function called by the owner to create a new open lease
     * @param _profileId The id of the owner
     * @param _rentAmount The amount of the rent in fiat
     * @param _paymentToken The address of the token used for payment
     * @param _rentPaymentInterval The minimum interval between each rent payment
     * @param _currencyPair The currency pair used for rent price & payment | "CRYPTO" if rent in token or ETH
     * @param _startDate The start date of the lease
     */
    function createOpenLease(
        uint256 _profileId,
        uint256 _rentAmount,
        address _paymentToken,
        uint256 _rentPaymentInterval,
        string calldata _currencyPair,
        uint256 _startDate,
        uint256 _platformId
    )
        external
        //        string calldata _metaData
        onlyTrustOwner(_profileId)
        returns (uint256)
    {
        Lease storage lease = leases[_leaseIds.current()];
        lease.ownerId = _profileId;
        lease.tenantId = 0;
        lease.paymentData.rentAmount = _rentAmount;
        lease.totalNumberOfRents = 0;
        lease.paymentData.paymentToken = _paymentToken;
        lease.paymentData.currencyPair = _currencyPair;
        lease.rentPaymentInterval = _rentPaymentInterval;
        lease.startDate = _startDate;
        lease.status = LeaseStatus.PENDING;
        lease.platformId = _platformId;
        //        lease.metaData = _metaData;

        emit LeaseCreated(
            _leaseIds.current(),
            0,
            _profileId,
            0,
            _startDate,
            _rentPaymentInterval,
            _platformId
            //            _metaData
        );

        emit LeasePaymentDataUpdated(_leaseIds.current(), _rentAmount, _paymentToken, _currencyPair);

        uint256 leaseId = _leaseIds.current();
        _leaseIds.increment();

        return leaseId;
    }

    /**
     * @notice Function called by a tenant to create a proposal for an open lease
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _totalNumberOfRents The amount of rent payments for the lease
     * @param _startDate The start date of the lease
     * @param _platformId The id of the platform on which the proposal was created
     * @param _cid The cid of the metadata
     */
    function submitProposal(
        uint256 _profileId,
        uint256 _leaseId,
        uint8 _totalNumberOfRents,
        uint256 _startDate,
        uint256 _platformId,
        string calldata _cid
    ) external onlyTrustOwner(_profileId) {
        _validateProposal(_leaseId, _profileId, _cid);

        proposals[_leaseId][_profileId] = Proposal({
            ownerId: _profileId,
            totalNumberOfRents: _totalNumberOfRents,
            startDate: _startDate,
            platformId: _platformId,
            metaData: _cid
        });

        emit ProposalSubmitted(_leaseId, _profileId, _totalNumberOfRents, _startDate, _platformId, _cid);
    }

    /**
     * @notice Function called by a potential tenant to create a new open proposal
     * @param _profileId The id of the proposal maker
     * @param _cid The cid of the metadata with the proposal details
     */
    function createOpenProposal(
        uint256 _profileId,
        uint256 _platformId,
        string calldata _cid
    ) external onlyTrustOwner(_profileId) {
        uint256 openProposalId = _openProposalIds.current();
        openProposals[openProposalId] = OpenProposal({
            ownerId: _profileId,
            status: ProposalStatus.PENDING,
            platformId: _platformId,
            cid: _cid
        });

        _openProposalIds.increment();

        emit OpenProposalSubmitted(openProposalId, _platformId, _cid);
    }

    function validateProposal(
        uint256 _profileId,
        uint256 _tenantId,
        uint256 _leaseId
    ) external onlyTrustOwner(_profileId) {
        Lease storage lease = leases[_leaseId];
        require(lease.ownerId == _profileId, "Lease: Only owner can validate proposal");
        require(lease.status == LeaseStatus.PENDING, "Lease: Lease is not open");

        Proposal memory proposal = proposals[_leaseId][_tenantId];

        lease.tenantId = proposal.ownerId;
        lease.totalNumberOfRents = proposal.totalNumberOfRents;
        lease.startDate = proposal.startDate;
        lease.proposalId = _tenantId;

        //Rent id starts at 0 as it will be the multiplicator for the Payment Intervals
        for (uint8 i = 0; i < lease.totalNumberOfRents; i++) {
            lease.rentPayments.push(TransactionPayment(0, false, 0, 0, PaymentStatus.PENDING));
        }

        lease.status = LeaseStatus.ACTIVE;

        emit LeaseUpdated(_tenantId, proposal.totalNumberOfRents, proposal.startDate);
    }

    function updateProposal() external {}

    function updateOpenProposal() external {}

    /**
     * @notice Called by the tenant to update the lease metadata
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _newCid The new IPFS URI of the lease metadata
     */
    function updateLeaseMetaData(
        uint256 _profileId,
        uint256 _leaseId,
        string memory _newCid
    ) external onlyTrustOwner(_profileId) {
        require(bytes(_newCid).length == 46, "Lease: Invalid cid");

        Lease storage lease = leases[_leaseId];
        lease.metaData = _newCid;

        emit LeaseMetaDataUpdated(_leaseId, _newCid);
    }

    /**
     * @notice Called by the tenant or the owner to decline the lease proposition
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     */
    function declineLease(uint256 _profileId, uint256 _leaseId) external onlyTrustOwner(_profileId) {
        isValid(_leaseId);

        Lease storage lease = leases[_leaseId];
        require(_profileId == lease.ownerId || _profileId == lease.tenantId, "Lease: Not an actor of this lease");
        require(lease.status == LeaseStatus.PENDING, "Lease: Lease was already validated");

        lease.status = LeaseStatus.CANCELLED;

        emit UpdateLeaseStatus(_leaseId, LeaseStatus.CANCELLED);
    }

    //TODO check if this is still ok with open Leases (tenantId == 0 should prevent spam validation, but consider adding an OPEN status for clarity & filtering)
    /**
     * @notice Called by the tenant to validate the lease
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     */
    function validateLease(uint256 _profileId, uint256 _leaseId) external onlyTrustOwner(_profileId) {
        isValid(_leaseId);

        Lease storage lease = leases[_leaseId];
        require(_profileId == lease.tenantId, "Lease: Only the tenant can call this function");
        require(lease.status == LeaseStatus.PENDING, "Lease: Lease is not pending");

        lease.status = LeaseStatus.ACTIVE;

        emit UpdateLeaseStatus(_leaseId, LeaseStatus.ACTIVE);
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
     * @notice Can be called by the owner to mark a rent as not paid after the rent payment limit time is reached
     * @param _profileId The id of the owner
     * @param _leaseId The id of the lease
     * @param _rentId The id of the rent
     * @dev Only the owner of the lease can call this function
     */
    function markRentAsNotPaid(
        uint256 _profileId,
        uint256 _leaseId,
        uint256 _rentId
    ) external onlyTrustOwner(_profileId) {
        isValid(_leaseId);

        Lease memory _lease = leases[_leaseId];
        require(_lease.ownerId == _profileId, "Lease: Only the owner can perform this action");
        require(_lease.status == LeaseStatus.ACTIVE, "Lease: Lease is not Active");
        require(
            block.timestamp > _lease.startDate + _lease.rentPaymentInterval + _lease.rentPaymentInterval * _rentId,
            "Lease: Tenant still has time to pay"
        );

        TransactionPayment memory _rentPayment = _lease.rentPayments[_rentId];

        require(_rentPayment.paymentStatus != PaymentStatus.PAID, "Lease: Payment status should be PENDING");

        _updateRentStatus(_leaseId, _rentId, PaymentStatus.NOT_PAID);
        _updateLeaseAndPaymentsStatuses(_leaseId);

        emit RentNotPaid(_leaseId, _rentId);
    }

    /**
     * @notice Can be called by the owner or the tenant to cancel the remaining payments of a lease and make it as ended
     * @dev Both tenant and owner must call this function for the lease to be cancelled
     * @param _leaseId The id of the lease
     */
    function cancelLease(uint256 _profileId, uint256 _leaseId) external onlyTrustOwner(_profileId) {
        require(_leaseId <= _leaseIds.current(), "Lease does not exist");
        Lease storage lease = leases[_leaseId];
        require(_profileId == lease.ownerId || _profileId == lease.tenantId, "Lease: Not an actor of this lease");
        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");

        if (_profileId == lease.ownerId) {
            require(lease.cancellation.cancelledByOwner == false, "Lease already cancelled by owner");
            lease.cancellation.cancelledByOwner = true;
        } else {
            require(lease.cancellation.cancelledByTenant == false, "Lease already cancelled by tenant");
            lease.cancellation.cancelledByTenant = true;
        }

        emit CancellationRequested(_leaseId, lease.cancellation.cancelledByOwner, lease.cancellation.cancelledByTenant);

        if (lease.cancellation.cancelledByOwner && lease.cancellation.cancelledByTenant) {
            for (uint8 i = 0; i < lease.totalNumberOfRents; i++) {
                TransactionPayment storage rentPayment = lease.rentPayments[i];
                if (rentPayment.paymentStatus == PaymentStatus.PENDING) {
                    //TODO add here the logic to mark as NOT_PAID the overdue rent payments ?
                    _updateRentStatus(_leaseId, i, PaymentStatus.CANCELLED);
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
    function reviewLease(
        uint256 _profileId,
        uint256 _leaseId,
        string calldata _reviewUri
    ) external onlyTrustOwner(_profileId) {
        isValid(_leaseId);
        Lease storage lease = leases[_leaseId];
        require(_profileId == lease.ownerId || _profileId == lease.tenantId, "Lease: Not an actor of this lease");
        require(lease.status == LeaseStatus.ENDED, "Lease: Lease is still not finished");

        if (_profileId == lease.tenantId) {
            require(!lease.reviewStatus.tenantReviewed, "Lease: Tenant already reviewed");
            lease.reviewStatus.tenantReviewUri = _reviewUri;
            lease.reviewStatus.tenantReviewed = true;
            emit LeaseReviewedByTenant(_leaseId, _reviewUri);
        } else {
            require(!lease.reviewStatus.ownerReviewed, "Lease: Owner already reviewed");
            lease.reviewStatus.ownerReviewUri = _reviewUri;
            lease.reviewStatus.ownerReviewed = true;
            emit LeaseReviewedByOwner(_leaseId, _reviewUri);
        }
    }

    /**
     * @notice Function to update the payment status & potential issues of a rent payment
     * @param _leaseId The id of the lease
     * @param _rentId The rent payment id
     * @param _withoutIssues "true" if the tenant had no issues with the rented property during this rent period
     * @dev Only the payment manager contract can call this function
     */
    function validateRentPayment(uint256 _leaseId, uint256 _rentId, bool _withoutIssues) external onlyRole(PAYMENT_MANAGER_ROLE) {
        TransactionPayment storage rentPayment = leases[_leaseId].rentPayments[_rentId];
        rentPayment.paymentStatus = PaymentStatus.PAID;
        rentPayment.withoutIssues = _withoutIssues;
        rentPayment.validationDate = block.timestamp;

        _updateLeaseAndPaymentsStatuses(_leaseId);
    }

    // =========================== Private functions ===========================

    /**
     * @notice Private function to update the payment status of a rent payment
     * @param _leaseId The id of the lease
     * @param _rentId The rent payment id
     * @param _paymentStatus The new payment status
     */
    function _updateRentStatus(uint256 _leaseId, uint256 _rentId, PaymentStatus _paymentStatus) private {
        TransactionPayment storage rentPayment = leases[_leaseId].rentPayments[_rentId];
        rentPayment.paymentStatus = _paymentStatus;
    }

    //TODO: Check if this function can be gas-optimized
    /**
     * @notice Private function checking whether the lease is ended or not
     * @param _leaseId The id of the lease
     */
    function _updateLeaseAndPaymentsStatuses(uint256 _leaseId) private {
        Lease storage lease = leases[_leaseId];

        for (uint8 i = 0; i < lease.totalNumberOfRents; i++) {
            TransactionPayment storage rentPayment = lease.rentPayments[i];
            if (rentPayment.paymentStatus == PaymentStatus.PENDING) {
                return;
            }
        }
        lease.status = LeaseStatus.ENDED;

        emit UpdateLeaseStatus(_leaseId, lease.status);
    }

    /**
     * @notice Private function to validate a proposal
     * @param _leaseId The id of the lease
     * @param _profileId The id of the profile
     * @param _cid The IPFS cid of the proposal
     */
    function _validateProposal(uint256 _leaseId, uint256 _profileId, string calldata _cid) private view {
        Lease storage lease = leases[_leaseId];
        require(lease.status == LeaseStatus.PENDING, "Lease: Lease is not open");
        require(bytes(_cid).length == 46, "Lease: Invalid cid");
        require(lease.ownerId != _profileId, "Lease: Owner cannot submit proposal");
        require(proposals[_leaseId][_profileId].ownerId != _profileId, "Lease: Proposal already submitted");
    }

    // =============================== Events ==================================

    event LeaseCreated(
        uint256 leaseId,
        uint256 tenantId,
        uint256 ownerId,
        uint8 totalNumberOfRents,
        uint256 startDate,
        uint256 rentPaymentInterval,
        uint256 platformId
        //        string metadata
    );

    event LeasePaymentDataUpdated(uint256 leaseId, uint256 rentAmount, address paymentToken, string currencyPair);

    event LeaseUpdated(uint256 tenantId, uint8 totalNumberOfRents, uint256 startDate);

    event ProposalSubmitted(
        uint256 leaseId,
        uint256 tenantId,
        uint8 totalNumberOfRents,
        uint256 startDate,
        uint256 platformId,
        string metaData
    );

    event OpenProposalSubmitted(uint256 openProposalId, uint256 platformId, string cid);

    event RentPaymentIssueStatusUpdated(uint256 leaseId, uint256 rentId, bool withoutIssues);

    event RentNotPaid(uint256 leaseId, uint256 rentId);

    event SetRentToPending(uint256 leaseId, uint256 rentId);

    event UpdateLeaseStatus(uint256 leaseId, LeaseStatus status);

    event CancellationRequested(uint256 leaseId, bool cancelledByOwner, bool cancelledByTenant);

    event LeaseReviewedByOwner(uint256 leaseId, string reviewUri);

    event LeaseReviewedByTenant(uint256 leaseId, string reviewUri);

    event LeaseMetaDataUpdated(uint256 leaseId, string metaData);

    /**
     * @notice Emitted after the protocol fee was updated
     * @param _protocolFeeRate The new protocol fee
     */
    event ProtocolFeeRateUpdated(uint16 _protocolFeeRate);

    /**
     * @notice Emitted after a platform withdraws its balance
     * @param _platformId The Platform ID to which the balance is transferred.
     * @param _token The address of the token used for the payment.
     * @param _amount The amount transferred.
     */
    event FeesClaimed(uint256 _platformId, address indexed _token, uint256 _amount);

    // =========================== Modifiers ==============================

    /**
     * @notice Check if the msg sender is the owner of the given user ID
     * @param _profileId The Trust ID of the user
     */
    modifier onlyTrustOwner(uint256 _profileId) {
        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
        _;
    }

    //    //TODO Check if this modifier is needed when payment functions are merged
    //    /**
    //     * @notice Restricts the actions to the tenant of the ACTIVE lease
    //     * @param _profileId The Trust ID of the user
    //     * @param _leaseId The ID of the lease
    //     */
    //    modifier tenantCheck(uint256 _profileId, uint256 _leaseId) {
    //        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
    //        isValid(_leaseId);
    //        Lease memory lease = leases[_leaseId];
    //        require(_profileId == lease.tenantId, "Lease: Only the tenant can call this function");
    //        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
    //        _;
    //    }
    //
    //    //TODO Check if this modifier is needed when payment functions are merged
    //    /**
    //     * @notice Restricts the actions to the owner of the ACTIVE lease
    //     * @param _profileId The Trust ID of the user
    //     * @param _leaseId The ID of the lease
    //     */
    //    modifier ownerCheck(uint256 _profileId, uint256 _leaseId) {
    //        require(trustIdContract.ownerOf(_profileId) == msg.sender, "Lease: Not TrustId owner");
    //        isValid(_leaseId);
    //        Lease memory lease = leases[_leaseId];
    //        require(_profileId == lease.ownerId, "Lease: Only the owner can call this function");
    //        require(lease.status == LeaseStatus.ACTIVE, "Lease is not Active");
    //        _;
    //    }
}
