// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/IP2pYieldProxy.sol";

/// @title Interface for the P2P Ethena proxy adapter
/// @notice Extends the base proxy interface with Ethena specific helper flows for managing cooldowns and withdrawals.
interface IP2pEthenaProxy is IP2pYieldProxy {
    /// @notice Redeems assets and starts a cooldown to claim the converted underlying asset.
    /// @param _assets Amount of USDe (assets) to redeem and start cooling down.
    /// @return shares Amount of sUSDe shares burned during the call.
    function cooldownAssets(uint256 _assets) external returns (uint256 shares);

    /// @notice Allows the P2P operator to cooldown the entire accrued-rewards portion.
    /// @return shares Amount of sUSDe shares burned during the call.
    function cooldownAssetsAccruedRewards() external returns (uint256 shares);

    /// @notice Redeems shares into assets and starts a cooldown to claim the converted underlying asset.
    /// @param _shares Amount of sUSDe shares to redeem into a cooldown request.
    /// @return assets Amount of USDe that will be claimable after the cooldown finishes.
    function cooldownShares(uint256 _shares) external returns (uint256 assets);

    /// @notice Withdraws assets after a cooldown has elapsed.
    function withdrawAfterCooldown() external;

    /// @notice Allows the P2P operator to withdraw cooled-down assets up to the accrued rewards portion.
    function withdrawAfterCooldownAccruedRewards() external;

    /// @notice Withdraws assets without a cooldown when the vault supports instant withdrawals.
    /// @param _assets Amount of USDe assets to redeem via `withdraw`.
    function withdrawWithoutCooldown(uint256 _assets) external;

    /// @notice Allows the P2P operator to instantly withdraw the currently accrued rewards portion.
    function withdrawWithoutCooldownAccruedRewards() external;

    /// @notice Redeems shares without cooldown when the vault supports instant withdrawals.
    /// @param _shares Amount of sUSDe shares to redeem via `redeem`.
    function redeemWithoutCooldown(uint256 _shares) external;
}

