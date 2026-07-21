// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title Interface for the P2P Maple proxy adapter
/// @notice Exposes Maple-specific helper flows for depositing, requesting withdrawal, and redeeming.
/// Maple pools are ERC-4626 with a FIFO withdrawal queue managed by WithdrawalManagerQueue.
/// The flow is: deposit → requestRedeem → (pool delegate processes) → redeem.
interface IP2pMapleProxy {
    /// @notice Withdraws (redeems) shares from the Maple pool after they have been processed.
    /// @param _pool The Maple pool address.
    /// @param _shares Amount of pool shares to redeem.
    function withdraw(address _pool, uint256 _shares) external;

    /// @notice Withdraws only the accrued-rewards portion from a Maple pool.
    /// @param _pool The Maple pool address.
    function withdrawAccruedRewards(address _pool) external;

    /// @notice Requests redemption of shares from the Maple pool.
    ///         Shares are escrowed in the WithdrawalManagerQueue until the pool delegate processes them.
    /// @param _pool The Maple pool address.
    /// @param _shares Amount of pool shares to request for redemption.
    /// @return escrowedShares_ The number of shares actually escrowed.
    function requestRedeem(address _pool, uint256 _shares) external returns (uint256 escrowedShares_);

    /// @notice Requests redemption for the accrued-rewards portion only.
    /// @param _pool The Maple pool address.
    /// @return escrowedShares_ The number of shares escrowed.
    function requestRedeemAccruedRewards(address _pool) external returns (uint256 escrowedShares_);

    /// @notice Cancels or reduces a pending withdrawal request.
    /// @param _pool The Maple pool address.
    /// @param _shares Amount of shares to remove from the queue.
    /// @return sharesReturned_ Shares returned to the proxy.
    function removeShares(address _pool, uint256 _shares) external returns (uint256 sharesReturned_);

    /// @notice Emitted when a redemption request is submitted.
    /// @param pool The Maple pool address.
    /// @param shares The amount of shares requested.
    /// @param escrowedShares The amount of shares escrowed.
    event P2pMapleProxy__RedemptionRequested(address indexed pool, uint256 shares, uint256 escrowedShares);

    /// @notice Emitted when shares are removed from the withdrawal queue.
    /// @param pool The Maple pool address.
    /// @param sharesRemoved The amount of shares removed.
    event P2pMapleProxy__SharesRemoved(address indexed pool, uint256 sharesRemoved);
}
