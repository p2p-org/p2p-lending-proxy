// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryIsReferenceP2pYieldProxyAllowed {
    function isReferenceP2pYieldProxyAllowed(address _referenceP2pYieldProxy) external view returns (bool);
}

