// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";

/// @title Interface for the Ethena-specific proxy factory
/// @notice Extends the base factory surface while providing a distinct ERC165 identifier for Ethena deployments.
interface IP2pEthenaProxyFactory is IP2pYieldProxyFactory {}

