// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../common/AllowedCalldataChecker.sol";
import "../P2pYieldProxyErrors.sol";

abstract contract AllowedCalldataCheckerImmutable {
    IAllowedCalldataChecker internal immutable i_allowedCalldataChecker;

    constructor(address _allowedCalldataCheckerAddress) {
        require(_allowedCalldataCheckerAddress != address(0), P2pYieldProxy__ZeroAllowedCalldataChecker());
        i_allowedCalldataChecker = IAllowedCalldataChecker(_allowedCalldataCheckerAddress);
    }

    function getAllowedCalldataChecker() public view virtual returns (address) {
        return address(i_allowedCalldataChecker);
    }

    function _allowedCalldataChecker() internal view virtual returns (IAllowedCalldataChecker) {
        return i_allowedCalldataChecker;
    }
}
