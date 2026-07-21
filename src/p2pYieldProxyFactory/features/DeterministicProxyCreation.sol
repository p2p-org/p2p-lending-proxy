// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts/proxy/Clones.sol";
import "../../p2pYieldProxy/P2pYieldProxy.sol";
import "../IP2pYieldProxyFactory.sol";
import "../P2pYieldProxyFactoryErrors.sol";
import "../interfaces/IFactoryPredictProxyAddress.sol";
import "../storage/AllProxiesStorage.sol";
import "../storage/ReferenceP2pYieldProxiesStorage.sol";

abstract contract DeterministicProxyCreation is
    IFactoryPredictProxyAddress,
    ReferenceP2pYieldProxiesStorage,
    AllProxiesStorage
{
    function predictP2pYieldProxyAddress(address _referenceP2pYieldProxy, address _client, uint96 _clientBasisPoints)
        public
        view
        virtual
        override(IFactoryPredictProxyAddress)
        returns (address)
    {
        require(
            s_referenceP2pYieldProxies[_referenceP2pYieldProxy],
            P2pYieldProxyFactory__ReferenceP2pYieldProxyNotAllowed(_referenceP2pYieldProxy)
        );
        return Clones.predictDeterministicAddress(_referenceP2pYieldProxy, _getSalt(_referenceP2pYieldProxy, _client, _clientBasisPoints));
    }

    function _getOrCreateP2pYieldProxy(address _referenceP2pYieldProxy, uint96 _clientBasisPoints)
        internal
        returns (P2pYieldProxy p2pYieldProxy)
    {
        address p2pYieldProxyAddress =
            predictP2pYieldProxyAddress(_referenceP2pYieldProxy, msg.sender, _clientBasisPoints);
        if (p2pYieldProxyAddress.code.length > 0) {
            return P2pYieldProxy(p2pYieldProxyAddress);
        }

        p2pYieldProxy = P2pYieldProxy(
            Clones.cloneDeterministic(
                _referenceP2pYieldProxy,
                _getSalt(_referenceP2pYieldProxy, msg.sender, _clientBasisPoints)
            )
        );

        p2pYieldProxy.initialize(msg.sender, _clientBasisPoints);
        s_allProxies.push(address(p2pYieldProxy));

        emit IP2pYieldProxyFactory.P2pYieldProxyFactory__ProxyCreated(address(p2pYieldProxy), msg.sender, _clientBasisPoints);
    }

    function _getSalt(address _referenceP2pYieldProxy, address _clientAddress, uint96 _clientBasisPoints)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_referenceP2pYieldProxy, _clientAddress, _clientBasisPoints));
    }
}
