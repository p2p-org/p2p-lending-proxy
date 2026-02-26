// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev 256-bit packed struct for withdrawal accounting.
struct Withdrawn {
    uint208 amount;
    uint48 lastFeeCollectionTime;
}
