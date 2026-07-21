// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../common/AllowedCalldataChecker.sol";
import "./CalldataAllowed.sol";
import "../immutables/AllowedCalldataCheckerImmutable.sol";

abstract contract AllowedCalldataCheckerProvider is CalldataAllowed, AllowedCalldataCheckerImmutable {
    constructor(address _allowedCalldataCheckerAddress)
        AllowedCalldataCheckerImmutable(_allowedCalldataCheckerAddress)
    {}

    function _allowedCalldataChecker()
        internal
        view
        virtual
        override(CalldataAllowed, AllowedCalldataCheckerImmutable)
        returns (IAllowedCalldataChecker)
    {
        return super._allowedCalldataChecker();
    }
}
