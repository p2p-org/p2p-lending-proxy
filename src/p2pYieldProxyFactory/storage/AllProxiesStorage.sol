// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../interfaces/IFactoryGetAllProxies.sol";

abstract contract AllProxiesStorage is IFactoryGetAllProxies {
    address[] internal s_allProxies;

    function getAllProxies()
        public
        view
        virtual
        override(IFactoryGetAllProxies)
        returns (address[] memory)
    {
        return s_allProxies;
    }
}
