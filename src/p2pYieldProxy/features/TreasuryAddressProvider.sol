// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../immutables/TreasuryImmutable.sol";

abstract contract TreasuryAddressProvider is TreasuryImmutable {
    constructor(address _p2pTreasury) TreasuryImmutable(_p2pTreasury) {}

    function _p2pTreasuryAddress() internal view virtual returns (address) {
        return i_p2pTreasury;
    }
}
