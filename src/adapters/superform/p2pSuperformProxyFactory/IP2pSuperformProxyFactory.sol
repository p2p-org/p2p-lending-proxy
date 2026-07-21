// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;
import "../../../@permit2/interfaces/IAllowanceTransfer.sol";
import "../../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";

/// @dev External interface of P2pSuperformProxyFactory
interface IP2pSuperformProxyFactory is IP2pYieldProxyFactory {
    /// @dev Checks if the claim is valid
    /// @param _p2pOperatorToCheck The P2pOperator to check
    function checkClaim(
        address _p2pOperatorToCheck
    ) external view;
}
