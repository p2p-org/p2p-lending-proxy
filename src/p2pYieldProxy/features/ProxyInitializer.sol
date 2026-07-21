// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/security/ReentrancyGuardUpgradeable.sol";
import "../IP2pYieldProxy.sol";
import "../P2pYieldProxyErrors.sol";
import "./FactoryCallable.sol";
import "../storage/ClientStorage.sol";
import "../storage/ClientBasisPointsStorage.sol";
import "../interfaces/IProxyInitialize.sol";

abstract contract ProxyInitializer is
    IProxyInitialize,
    ReentrancyGuardUpgradeable,
    FactoryCallable,
    ClientStorage,
    ClientBasisPointsStorage
{
    function initialize(
        address _client,
        uint96 _clientBasisPoints
    )
        public
        virtual
        override(IProxyInitialize)
        initializer
        onlyFactory
    {
        __ReentrancyGuard_init();

        require(
            _clientBasisPoints > 0 && _clientBasisPoints <= 10_000,
            P2pYieldProxy__InvalidClientBasisPoints(_clientBasisPoints)
        );

        s_client = _client;
        s_clientBasisPoints = _clientBasisPoints;

        emit IP2pYieldProxy.P2pYieldProxy__Initialized();
    }
}
