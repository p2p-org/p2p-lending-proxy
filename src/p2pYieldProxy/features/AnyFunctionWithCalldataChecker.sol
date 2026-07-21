// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../common/AllowedCalldataChecker.sol";
import "./AnyFunctionExecutor.sol";
import "./CalldataAllowed.sol";
import "./AllowedCalldataCheckerProvider.sol";

abstract contract AnyFunctionWithCalldataChecker is AnyFunctionExecutor, AllowedCalldataCheckerProvider {
    constructor(address _allowedCalldataCheckerAddress)
        AllowedCalldataCheckerProvider(_allowedCalldataCheckerAddress)
    {}

    function _allowedCalldataChecker()
        internal
        view
        virtual
        override(CalldataAllowed, AllowedCalldataCheckerProvider)
        returns (IAllowedCalldataChecker)
    {
        return AllowedCalldataCheckerProvider._allowedCalldataChecker();
    }
}
