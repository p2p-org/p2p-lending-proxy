// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";

/// @dev External interface of P2pSuperformProxyFactory
interface IP2pSuperformProxyFactory is IP2pYieldProxyFactory {
    /// @notice Validates that an address is the authorised P2pOperator for reward claims
    /// @param _p2pOperatorToCheck Address being validated as the active P2pOperator
    function checkClaim(address _p2pOperatorToCheck) external view;
}
