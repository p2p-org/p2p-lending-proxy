// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryPredictProxyAddress {
    function predictP2pYieldProxyAddress(address _referenceP2pYieldProxy, address _client, uint96 _clientBasisPoints)
        external
        view
        returns (address proxyAddress);
}
