// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../P2pYieldProxyErrors.sol";
import "../features/FactoryCallable.sol";

abstract contract FactoryImmutable is FactoryCallable {
    IP2pYieldProxyFactory internal immutable i_factory;

    constructor(address _factoryAddress) {
        require(_factoryAddress != address(0), P2pYieldProxy__ZeroAddressFactory());
        i_factory = IP2pYieldProxyFactory(_factoryAddress);
    }

    function getFactory() public view virtual returns (address) {
        return address(i_factory);
    }

    function _factory() internal view override returns (IP2pYieldProxyFactory) {
        return i_factory;
    }
}
