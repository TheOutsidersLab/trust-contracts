// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


/**
 * @title Lease Interface
 * @notice This contracts allows owners to create Leases & tenants to pay their rent.
 * @author Quentin DC
 */

interface ILease {
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

    struct PaymentData {
        uint256 rentAmount;
        address paymentToken;
        string currencyPair;
    }

    struct Cancellation {
        bool cancelledByOwner;
        bool cancelledByTenant;
    }

    struct ReviewStatus {
        bool ownerReviewed;
        bool tenantReviewed;
        string ownerReviewUri;
        string tenantReviewUri;
    }

    struct Proposal {
        uint256 ownerId;
        uint8 totalNumberOfRents;
        uint256 startDate;
        uint256 platformId;
        string metaData;
    }

    struct OpenProposal {
        uint256 ownerId;
        ProposalStatus status;
        uint256 platformId;
        string cid;
    }

    struct TransactionPayment {
        uint256 validationDate;
        bool withoutIssues;
        int256 exchangeRate;
        uint256 exchangeRateTimestamp;
        PaymentStatus paymentStatus;
    }

    function getPayments(uint256 _leaseId) external view returns (TransactionPayment[] memory rentPayments);

    function getProposal(uint256 _leaseId, uint256 _ownerId) external view returns (Proposal memory proposal);

    function getLease(uint256 _leaseId) external view returns (Lease memory lease);

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
    ) external returns (uint256 leaseId);

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
    returns (uint256);

    function submitProposal(
        uint256 _profileId,
        uint256 _leaseId,
        uint8 _totalNumberOfRents,
        uint256 _startDate,
        uint256 _platformId,
        string calldata _cid
    ) external;

    function createOpenProposal(
        uint256 _profileId,
        uint256 _platformId,
        string calldata _cid
    ) external;

    function validateProposal(
        uint256 _profileId,
        uint256 _tenantId,
        uint256 _leaseId
    ) external;

    function updateProposal() external;

    function updateOpenProposal() external;

    function updateLeaseMetaData(
        uint256 _profileId,
        uint256 _leaseId,
        string memory _newCid
    ) external;

    function declineLease(uint256 _profileId, uint256 _leaseId) external;

    function validateLease(uint256 _profileId, uint256 _leaseId) external;

    function markRentAsNotPaid(
        uint256 _profileId,
        uint256 _leaseId,
        uint256 _rentId
    ) external;

    function cancelLease(uint256 _profileId, uint256 _leaseId) external;

    function reviewLease(
        uint256 _profileId,
        uint256 _leaseId,
        string calldata _reviewUri
    ) external;

    function validateRentPayment(uint256 _leaseId, uint256 _rentId, bool _withoutIssues) external;

    function isValid(uint256 _leaseId) external;
}
