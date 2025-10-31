// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title Interface for the P2P Ethena proxy adapter
/// @notice Exposes Ethena specific helper flows for managing cooldowns and withdrawals.
interface IP2pEthenaProxy {
    /// @notice Redeems assets and starts a cooldown to claim the converted underlying asset.
    /// @param _assets Amount of USDe (assets) to redeem.
    /// @return shares Amount of sUSDe shares burned during the call.
    function cooldownAssets(uint256 _assets) external returns (uint256 shares);

    /// @notice Allows the P2P operator to cooldown only the accrued rewards portion.
    /// @return shares Amount of sUSDe shares burned during the call.
    function cooldownAssetsAccruedRewards() external returns (uint256 shares);

    /// @notice Redeems shares into assets and starts a cooldown to claim the converted underlying asset.
    /// @param _shares Amount of sUSDe shares to redeem.
    /// @return assets Amount of USDe that will be claimable after the cooldown finishes.
    function cooldownShares(uint256 _shares) external returns (uint256 assets);

    /// @notice Withdraw assets after the cooldown has elapsed.
    function withdrawAfterCooldown() external;

    /// @notice Allows the P2P operator to withdraw cooled-down assets up to accrued rewards.
    function withdrawAfterCooldownAccruedRewards() external;

    /// @notice Withdraw assets without cooldown if the vault supports instant withdrawals.
    /// @param _assets Amount of USDe assets to redeem via `withdraw`.
    function withdrawWithoutCooldown(uint256 _assets) external;

    /// @notice Allows the P2P operator to withdraw assets instantly up to accrued rewards.
    function withdrawWithoutCooldownAccruedRewards() external;

    /// @notice Redeem shares without cooldown if the vault supports instant withdrawals.
    /// @param _shares Amount of sUSDe shares to redeem via `redeem`.
    function redeemWithoutCooldown(uint256 _shares) external;
}

