// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CroesusTokenERC20
 * @notice Dummy ERC20 contract used for testing purposes
 * @author Quentin DC @ Starton Hackathon 2022
 */
contract CroesusTokenERC20 is ERC20 {
    address public owner;

    constructor() ERC20("CroesusToken", "CRT") {
        _mint(msg.sender, 100000000 ether);
        owner = msg.sender;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}
