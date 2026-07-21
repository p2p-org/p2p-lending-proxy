// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../storage/ClientBasisPointsStorage.sol";

abstract contract FeeMath is ClientBasisPointsStorage {
    function calculateP2pFeeAmount(uint256 _amount) internal view returns (uint256 p2pFeeAmount) {
        if (_amount == 0) return 0;
        p2pFeeAmount = (_amount * (10_000 - s_clientBasisPoints) + 9999) / 10_000;
    }
}
