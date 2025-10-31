// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Interface for Ethena's StakedUSDe vault
/// @notice Extends the ERC-4626 interface with queued withdrawal helper flows.
interface IStakedUSDe is IERC4626 {
    /// @notice Redeems assets and starts a cooldown to claim the converted underlying asset.
    /// @param assets Amount of assets to redeem.
    /// @return shares Amount of shares burned during the cooldown request.
    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    /// @notice Redeems shares into assets and starts a cooldown to claim the converted underlying asset.
    /// @param shares Amount of shares to redeem.
    /// @return assets Amount of assets that will be claimable after the cooldown finishes.
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    /// @notice Claim the staking amount after the cooldown has finished.
    /// @param receiver Address that will receive the unlocked assets.
    function unstake(address receiver) external;
}

