// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../common/AllowedCalldataChecker.sol";
import "../P2pYieldProxyErrors.sol";

abstract contract AllowedCalldataByClientToP2pCheckerImmutable {
    IAllowedCalldataChecker internal immutable i_allowedCalldataByClientToP2pChecker;

    constructor(address _allowedCalldataByClientToP2pCheckerAddress) {
        require(
            _allowedCalldataByClientToP2pCheckerAddress != address(0),
            P2pYieldProxy__ZeroAllowedCalldataByClientToP2pChecker()
        );
        i_allowedCalldataByClientToP2pChecker = IAllowedCalldataChecker(_allowedCalldataByClientToP2pCheckerAddress);
    }

    function getAllowedCalldataByClientToP2pChecker() public view virtual returns (address) {
        return address(i_allowedCalldataByClientToP2pChecker);
    }

    function _allowedCalldataByClientToP2pChecker() internal view virtual returns (IAllowedCalldataChecker) {
        return i_allowedCalldataByClientToP2pChecker;
    }
}
