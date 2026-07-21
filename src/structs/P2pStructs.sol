// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev 256 bit struct
/// @custom:member amount Accumulated withdrawn amount
/// @custom:member lastFeeCollectionTime Last fee collection timestamp
struct Withdrawn {
    uint208 amount;
    uint48 lastFeeCollectionTime;
}
