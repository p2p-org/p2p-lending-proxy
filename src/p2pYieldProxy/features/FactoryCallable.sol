// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../P2pYieldProxyErrors.sol";

abstract contract FactoryCallable {
    function _factory() internal view virtual returns (IP2pYieldProxyFactory);

    modifier onlyFactory() {
        IP2pYieldProxyFactory factory = _factory();
        if (msg.sender != address(factory)) {
            revert P2pYieldProxy__NotFactoryCalled(msg.sender, factory);
        }
        _;
    }
}
