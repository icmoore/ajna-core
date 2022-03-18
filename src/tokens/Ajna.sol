// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AjnaToken is ERC20("AjnaToken", "AJNA") {
    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply);
    }

    function _beforeTokenTransfer(
        address from,
        address,
        uint256
    ) internal override {
        // This can be achived by setting _balances[address(this)] to the max value uint256.
        // But _balances are private variable in the OpenZeppelin ERC20 contract implementation.

        require(
            from != address(this),
            "Cannot transfer tokens from the contract itself"
        );
    }
}