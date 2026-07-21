// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title ICometRewards
/// @notice Minimal interface for Compound V3 CometRewards contract
interface ICometRewards {
    event RewardClaimed(
        address indexed src,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    /// @notice Claim rewards for `src` — no permission check, rewards always go to `src`
    /// @param comet The Comet market address
    /// @param src The account to claim for (rewards are sent to this address)
    /// @param shouldAccrue Whether to call comet.accrueAccount(src) first
    function claim(address comet, address src, bool shouldAccrue) external;
}
