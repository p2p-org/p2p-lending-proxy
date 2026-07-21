// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../interfaces/IFactoryIsReferenceP2pYieldProxyAllowed.sol";

abstract contract ReferenceP2pYieldProxiesStorage is IFactoryIsReferenceP2pYieldProxyAllowed {
    mapping(address => bool) internal s_referenceP2pYieldProxies;

    function isReferenceP2pYieldProxyAllowed(address _referenceP2pYieldProxy)
        public
        view
        virtual
        override
        returns (bool)
    {
        return s_referenceP2pYieldProxies[_referenceP2pYieldProxy];
    }
}

