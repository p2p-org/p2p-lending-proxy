// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../P2pYieldProxyErrors.sol";

abstract contract TreasuryImmutable {
    address internal immutable i_p2pTreasury;

    constructor(address _p2pTreasury) {
        require(_p2pTreasury != address(0), P2pYieldProxy__ZeroAddressP2pTreasury());
        i_p2pTreasury = _p2pTreasury;
    }

    function getP2pTreasury() public view virtual returns (address) {
        return i_p2pTreasury;
    }
}
