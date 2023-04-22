// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Platform ID Contract
 * @author Quentin D.C
 */
contract PlatformId is ERC721, AccessControl {
    using Counters for Counters.Counter;

    uint8 constant MIN_HANDLE_LENGTH = 5;
    uint8 constant MAX_HANDLE_LENGTH = 31;

    // =========================== Enum ==============================

    // =========================== Variables ==============================

    /**
     * @notice Platform information struct
     * @param id the Platform Id
     * @param name the name of the platform
     * @param dataUri the IPFS URI of the Platform metadata
     * @param originLEaseFeeRate the %fee (per ten thousands) asked by the platform for each lease created on the platform.
     *        This fee is paid by the Lease creator to the platform on which the lease was created, as a percentage of each payment.
     * @param originProposalFeeRate the %fee (per ten thousands) asked by the platform for each created proposal on the platform
     *        This fee is paid by the Lease creator to the platform on which the proposal was created, as a percentage of each payment.
     * @param servicePostingFee the fee (flat) asked by the platform to post a service on the platform
     * @param proposalPostingFee the fee (flat) asked by the platform to post a proposal on the platform
     */
    struct Platform {
        uint256 id;
        string name;
        string dataUri;
        uint16 originLeaseFeeRate;
        uint16 originProposalFeeRate;
        uint256 leasePostingFee;
        uint256 proposalPostingFee;
    }

    /**
     * @notice Taken Platform name
     */
    mapping(string => bool) public takenNames;

    /**
     * @notice Platform ID to Platform struct
     */
    mapping(uint256 => Platform) public platforms;

    /**
     * @notice Address to PlatformId
     */
    mapping(address => uint256) public ids;

    /**
     * @notice Price to mint a platform id (in wei, upgradable)
     */
    uint256 public mintFee;

    /**
     * @notice Role granting Minting permission
     */
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    /**
     * @notice Platform Id counter
     */
    Counters.Counter private nextPlatformId;

    // =========================== Errors ==============================

    /**
     * @notice error thrown when input handle is 0 or more than 31 characters long.
     */
    error HandleLengthInvalid();

    /**
     * @notice error thrown when input handle contains restricted characters.
     */
    error HandleContainsInvalidCharacters();

    /**
     * @notice error thrown when input handle has an invalid first character.
     */
    error HandleFirstCharInvalid();

    // =========================== Initializers ==============================

    constructor() ERC721("UserId", "TID") {
        // Increment counter to start profile ids at index 1
        nextPlatformId.increment();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINT_ROLE, msg.sender);
        mintFee = 0;
    }

    // =========================== View functions ==============================

    /**
     * @notice Check whether the Platform Id is valid.
     * @param _platformId The Platform Id.
     */
    function isValid(uint256 _platformId) public view {
        require(_platformId > 0 && _platformId < nextPlatformId.current(), "Invalid platform ID");
    }

    /**
     * @notice Allows retrieval of a Platform Lease fee
     * @param _platformId The Platform Id
     * @return The Platform lease fee
     */
    function getOriginLeaseFeeRate(uint256 _platformId) external view returns (uint16) {
        isValid(_platformId);
        return platforms[_platformId].originLeaseFeeRate;
    }

    /**
     * @notice Allows retrieval of a Platform Proposal fee
     * @param _platformId The Platform Id
     * @return The Platform proposal fee
     */
    function getOriginProposalFeeRate(uint256 _platformId) external view returns (uint16) {
        isValid(_platformId);
        return platforms[_platformId].originProposalFeeRate;
    }

    /**
     * @notice Allows retrieval of a lease posting fee
     * @param _platformId The Platform Id
     * @return The Lease posting fee
     */
    function getLeasePostingFee(uint256 _platformId) external view returns (uint256) {
        isValid(_platformId);
        return platforms[_platformId].leasePostingFee;
    }

    /**
     * @notice Allows retrieval of a proposal posting fee
     * @param _platformId The Platform Id
     * @return The Proposal posting fee
     */
    function getProposalPostingFee(uint256 _platformId) external view returns (uint256) {
        isValid(_platformId);
        return platforms[_platformId].proposalPostingFee;
    }

    /**
     * @notice Allows retrieval of a Platform
     * @param _platformId The Platform Id
     * @return The Platform
     */
    function getPlatform(uint256 _platformId) external view returns (Platform memory) {
        isValid(_platformId);
        return platforms[_platformId];
    }

    /**
     * @dev Returns the total number of tokens in existence.
     */
    function totalSupply() public view returns (uint256) {
        return nextPlatformId.current() - 1;
    }

    // =========================== User functions ==============================

    /**
     * @notice Allows a platform to mint a new Platform Id.
     * @param _platformName Platform name
     */
    function mint(string calldata _platformName) public payable canMint(_platformName, msg.sender) returns (uint256) {
        _mint(msg.sender, nextPlatformId.current());
        return _afterMint(_platformName, msg.sender);
    }

    /**
     * @notice Allows a user to mint a new Platform Id and assign it to an eth address.
     * @dev You need to have MINT_ROLE to use this function
     * @param _platformName Platform name
     * @param _platformAddress Eth Address to assign the Platform Id to
     */
    function mintForAddress(
        string calldata _platformName,
        address _platformAddress
    ) public payable canMint(_platformName, _platformAddress) onlyRole(MINT_ROLE) returns (uint256) {
        _mint(_platformAddress, nextPlatformId.current());
        return _afterMint(_platformName, _platformAddress);
    }

    /**
     * @notice Update platform URI data.
     * @dev we are trusting the platform to provide the valid IPFS URI
     * @param _platformId The Platform Id
     * @param _newCid New IPFS URI
     */
    function updateProfileData(uint256 _platformId, string memory _newCid) public onlyPlatformOwner(_platformId) {
        require(bytes(_newCid).length == 46, "Invalid cid");

        platforms[_platformId].dataUri = _newCid;

        emit CidUpdated(_platformId, _newCid);
    }

    /**
     * @notice Allows a platform to update its Lease fee
     * @param _platformId The Platform Id
     * @param _originLeaseFeeRate Platform fee to update
     */
    function updateOriginLeaseFeeRate(
        uint256 _platformId,
        uint16 _originLeaseFeeRate
    ) public onlyPlatformOwner(_platformId) {
        platforms[_platformId].originLeaseFeeRate = _originLeaseFeeRate;
        emit OriginLeaseFeeRateUpdated(_platformId, _originLeaseFeeRate);
    }

    /**
     * @notice Allows a platform to update its Proposal fee
     * @param _platformId The Platform Id
     * @param _originProposalFeeRate Platform fee to update
     */
    function updateOriginProposalFeeRate(
        uint256 _platformId,
        uint16 _originProposalFeeRate
    ) public onlyPlatformOwner(_platformId) {
        platforms[_platformId].originProposalFeeRate = _originProposalFeeRate;
        emit OriginProposalFeeRateUpdated(_platformId, _originProposalFeeRate);
    }

    /**
     * @notice Allows a platform to update the lease posting fee for the platform
     * @param _platformId The platform Id of the platform
     * @param _leasePostingFee The new fee
     */
    function updateLeasePostingFee(
        uint256 _platformId,
        uint256 _leasePostingFee
    ) public onlyPlatformOwner(_platformId) {
        platforms[_platformId].leasePostingFee = _leasePostingFee;
        emit LeasePostingFeeUpdated(_platformId, _leasePostingFee);
    }

    /**
     * @notice Allows a platform to update the proposal posting fee for the platform
     * @param _platformId The platform Id of the platform
     * @param _proposalPostingFee The new fee
     */
    function updateProposalPostingFee(
        uint256 _platformId,
        uint256 _proposalPostingFee
    ) public onlyPlatformOwner(_platformId) {
        platforms[_platformId].proposalPostingFee = _proposalPostingFee;
        emit ProposalPostingFeeUpdated(_platformId, _proposalPostingFee);
    }

    // =========================== Owner functions ==============================

    /**
     * Updates the mint fee.
     * @param _mintFee The new mint fee
     */
    function updateMintFee(uint256 _mintFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintFee = _mintFee;
        emit MintFeeUpdated(_mintFee);
    }

    /**
     * Withdraws the contract balance to the admin.
     */
    function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool sent, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(sent, "Failed to withdraw Ether");
    }

    // =========================== Private functions ==============================

    /**
     * @notice Update Platform name mapping and emit event after mint.
     * @param _platformName Name of the platform.
     * @param _platformAddress Address of the platform.
     * @dev Increments the nextTokenId counter.
     */
    function _afterMint(string memory _platformName, address _platformAddress) private returns (uint256) {
        uint256 platformId = nextPlatformId.current();
        nextPlatformId.increment();
        Platform storage platform = platforms[platformId];
        platform.name = _platformName;
        platform.id = platformId;
        takenNames[_platformName] = true;
        ids[_platformAddress] = platformId;

        emit Mint(_platformAddress, platformId, _platformName, mintFee);

        return platformId;
    }

    /**
     * @notice Validate characters used in the handle, only alphanumeric, only lowercase characters, - and _ are allowed but only as first character
     * @param handle Handle to validate
     */
    function _validateHandle(string calldata handle) private pure {
        bytes memory byteHandle = bytes(handle);
        uint256 byteHandleLength = byteHandle.length;
        if (byteHandleLength < MIN_HANDLE_LENGTH || byteHandleLength > MAX_HANDLE_LENGTH) revert HandleLengthInvalid();

        bytes1 firstByte = bytes(handle)[0];
        if (firstByte == "-" || firstByte == "_") revert HandleFirstCharInvalid();

        for (uint256 i = 0; i < byteHandleLength; ) {
            if (
                (byteHandle[i] < "0" || byteHandle[i] > "z" || (byteHandle[i] > "9" && byteHandle[i] < "a")) &&
                byteHandle[i] != "-" &&
                byteHandle[i] != "_"
            ) revert HandleContainsInvalidCharacters();
            ++i;
        }
    }

    // =========================== Overrides ==============================

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    /**
     * @dev Override to prevent token transfer.
     */
    function _transfer(address, address, uint256) internal virtual override(ERC721) {
        revert("Token transfer is not allowed");
    }

    /**
     * @notice Implementation of the {IERC721Metadata-tokenURI} function.
     * @param tokenId The ID of the token
     */
    function tokenURI(uint256 tokenId) public view virtual override(ERC721) returns (string memory) {
        return _buildTokenURI(tokenId);
    }

    /**
     * @notice Builds the token URI
     * @param id The ID of the token
     */
    function _buildTokenURI(uint256 id) internal view returns (string memory) {
        string memory platformName = string.concat(platforms[id].name, ".any");
        string memory fontSizeStr = bytes(platforms[id].name).length <= 20 ? "60" : "40";

        bytes memory image = abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(
                bytes(
                    abi.encodePacked(
                        '<svg xmlns="http://www.w3.org/2000/svg" width="720" height="720"><rect width="100%" height="100%"/><svg xmlns="http://www.w3.org/2000/svg" width="150" height="150" version="1.2" viewBox="-200 -50 1000 1000"><path fill="#FFFFFF" d="M264.5 190.5c0-13.8 11.2-25 25-25H568c13.8 0 25 11.2 25 25v490c0 13.8-11.2 25-25 25H289.5c-13.8 0-25-11.2-25-25z"/><path fill="#FFFFFF" d="M265 624c0-13.8 11.2-25 25-25h543c13.8 0 25 11.2 25 25v56.5c0 13.8-11.2 25-25 25H290c-13.8 0-25-11.2-25-25z"/><path fill="#FFFFFF" d="M0 190.5c0-13.8 11.2-25 25-25h543c13.8 0 25 11.2 25 25V247c0 13.8-11.2 25-25 25H25c-13.8 0-25-11.2-25-25z"/></svg><text x="30" y="670" style="font: ',
                        fontSizeStr,
                        'px sans-serif;fill:#fff">',
                        platformName,
                        "</text></svg>"
                    )
                )
            )
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                platformName,
                                '", "image":"',
                                image,
                                unicode'", "description": "Platform ID"}'
                            )
                        )
                    )
                )
            );
    }

    // =========================== Modifiers ==============================

    /**
     * @notice Check if Platform is able to mint a new Platform ID.
     * @param _platformName name for the platform
     * @param _platformAddress address of the platform associated with the ID
     */
    modifier canMint(string calldata _platformName, address _platformAddress) {
        require(msg.value == mintFee, "Incorrect amount of ETH for mint fee");
        require(balanceOf(_platformAddress) == 0, "Platform already has a Platform ID");
        require(!takenNames[_platformName], "Name already taken");

        _validateHandle(_platformName);
        _;
    }

    /**
     * @notice Check if msg sender is the owner of a platform
     * @param _platformId the ID of the platform
     */
    modifier onlyPlatformOwner(uint256 _platformId) {
        require(ownerOf(_platformId) == msg.sender, "Not the owner");
        _;
    }

    // =========================== Events ==============================

    /**
     * @notice Emitted when new Platform ID is minted.
     * @param platformOwnerAddress Address of the owner of the PlatformID
     * @param platformId The Platform ID
     * @param platformName Name of the platform
     * @param fee Fee paid to mint the Platform ID
     */
    event Mint(address indexed platformOwnerAddress, uint256 platformId, string platformName, uint256 fee);

    /**
     * @notice Emit when Cid is updated for a platform.
     * @param platformId The Platform ID
     * @param newCid New URI
     */
    event CidUpdated(uint256 indexed platformId, string newCid);

    /**
     * @notice Emitted when mint fee is updated
     * @param mintFee The new mint fee
     */
    event MintFeeUpdated(uint256 mintFee);

    /**
     * @notice Emitted when the origin lease fee is updated for a platform
     * @param platformId The Platform Id
     * @param originLeaseFeeRate The new fee
     */
    event OriginLeaseFeeRateUpdated(uint256 platformId, uint16 originLeaseFeeRate);

    /**
     * @notice Emitted when the origin proposal fee is updated for a platform
     * @param platformId The Platform Id
     * @param originProposalFeeRate The new fee
     */
    event OriginProposalFeeRateUpdated(uint256 platformId, uint16 originProposalFeeRate);

    /**
     * @notice Emitted when the lease posting fee is updated for a platform
     * @param platformId The Platform Id
     * @param leasePostingFee The new fee
     */
    event LeasePostingFeeUpdated(uint256 platformId, uint256 leasePostingFee);

    /**
     * @notice Emitted when the proposal posting fee is updated for a platform
     * @param platformId The Platform Id
     * @param proposalPostingFee The new fee
     */
    event ProposalPostingFeeUpdated(uint256 platformId, uint256 proposalPostingFee);
}
