// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "./AccruedRewardsView.sol";
import "./TreasuryAddressProvider.sol";
import "./Withdrawable.sol";

abstract contract AccruedRewardsWithTreasury is AccruedRewardsView, TreasuryAddressProvider {
    constructor(address _p2pTreasury) TreasuryAddressProvider(_p2pTreasury) {}

    function _p2pTreasuryAddress()
        internal
        view
        virtual
        override(Withdrawable, TreasuryAddressProvider)
        returns (address)
    {
        return TreasuryAddressProvider._p2pTreasuryAddress();
    }
}
