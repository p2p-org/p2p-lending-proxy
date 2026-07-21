// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../IP2pYieldProxyFactory.sol";
import "../P2pYieldProxyFactoryErrors.sol";
import "../interfaces/IFactoryAddReferenceP2pYieldProxy.sol";
import "../storage/ReferenceP2pYieldProxiesStorage.sol";

abstract contract ReferenceP2pYieldProxyAllowlist is
    IFactoryAddReferenceP2pYieldProxy,
    ReferenceP2pYieldProxiesStorage
{
    function addReferenceP2pYieldProxy(address _referenceP2pYieldProxy) public virtual override {
        _authorizeReferenceP2pYieldProxyAllowlist();

        require(_referenceP2pYieldProxy != address(0), P2pYieldProxyFactory__ZeroReferenceP2pYieldProxyAddress());
        require(
            !s_referenceP2pYieldProxies[_referenceP2pYieldProxy],
            P2pYieldProxyFactory__ReferenceP2pYieldProxyAlreadyAllowed(_referenceP2pYieldProxy)
        );

        s_referenceP2pYieldProxies[_referenceP2pYieldProxy] = true;
        emit IP2pYieldProxyFactory.P2pYieldProxyFactory__ReferenceP2pYieldProxyAllowed(_referenceP2pYieldProxy);
    }

    function _authorizeReferenceP2pYieldProxyAllowlist() internal view virtual;
}

