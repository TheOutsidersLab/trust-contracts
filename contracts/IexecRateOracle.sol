// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Oracle} from "./libs/Oracle.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

/**
 * @title IexecRateOracle
 * @notice This contracts is used to call several IexecOracle contracts used for calculating Fiat rent conversions in token
 * @author Quentin DC @ Starton Hackathon 2022
 */
contract IexecRateOracle is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _callId;

    Oracle iexecOracle;
    address public oracleAddress = 0x36dA71ccAd7A67053f0a4d9D5f55b725C9A25A3E;

    mapping(string => bytes32) public rateIndexToOracleKey;

    mapping(string => RateData) public rateIndexToRateData;

    struct RateData {
        int256 rate;
        uint256 timestamp;
    }

    constructor() {
        _callId.increment();
        iexecOracle = Oracle(oracleAddress);
        rateIndexToOracleKey['EUR-ETH'] = 0x86bb403e4f69c1bb69a6968c4301a2c625418a9cd5a6bbea7c5c1154bde66350;
        rateIndexToOracleKey['USD-ETH'] = 0x3b2a4f0ea99be0c500ece0ce3c4444bc48c3121e73efde91be84bc6f579b088c;
        rateIndexToOracleKey['USD-SHI'] = 0x3b2a4f0ea99be0c500ece0ce3c4444bc48c3121e73efde91be84bc6f579b088c;
    }

    function addOrUpdateOracleKey(string memory _rateIndex, bytes32 _oracleKey) external onlyOwner {
        rateIndexToOracleKey[_rateIndex] = _oracleKey;
    }

    function updateOracleAddress (address _oracleAddress) external onlyOwner {
        oracleAddress = _oracleAddress;
    }

    function updateRate(string memory _currencyPair) external {
        bytes32 oracleKey = rateIndexToOracleKey[_currencyPair];
        require(oracleKey != 0, "Rate not found");

        (int256 _rate, uint256 _date) = iexecOracle.getInt(oracleKey);
        rateIndexToRateData[_currencyPair] = RateData(_rate, _date);
    }

    function getRate(string calldata _currencyPair) external view returns (int256 _rate, uint256 _date) {
        RateData memory rateData = rateIndexToRateData[_currencyPair];
        return (rateData.rate, rateData.timestamp);
    }
}
