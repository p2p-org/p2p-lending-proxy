// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Ethereum Vault Connector (EVC).
/// All EVault state-changing operations must be routed through EVC.call().
interface IEVC {
    /// @notice Calls a target contract on behalf of an account.
    /// @param targetContract The vault or contract to call.
    /// @param onBehalfOfAccount The account to act on behalf of (must be msg.sender or authorized).
    /// @param value ETH value to forward.
    /// @param data Encoded calldata for the target contract.
    /// @return result The return data from the call.
    function call(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory result);
}
