// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Maple Pool (ERC-4626 + withdrawal queue).
interface IMaplePool {
    // ERC-4626 deposit
    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);

    // ERC-4626 redeem (only works after withdrawal queue processing)
    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);

    // Withdrawal queue: request redemption
    function requestRedeem(uint256 shares_, address owner_) external returns (uint256 escrowShares_);

    // Cancel/reduce a pending withdrawal request
    function removeShares(uint256 shares_, address owner_) external returns (uint256 sharesReturned_);

    // ERC-4626 views
    function asset() external view returns (address asset_);
    function totalAssets() external view returns (uint256 totalAssets_);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account_) external view returns (uint256);
    function convertToAssets(uint256 shares_) external view returns (uint256 assets_);
    function convertToShares(uint256 assets_) external view returns (uint256 shares_);
    function previewRedeem(uint256 shares_) external view returns (uint256 assets_);
    function previewDeposit(uint256 assets_) external view returns (uint256 shares_);
    function maxDeposit(address receiver_) external view returns (uint256 maxAssets_);
    function maxRedeem(address owner_) external view returns (uint256 maxShares_);

    // Maple-specific views
    function manager() external view returns (address manager_);
    function unrealizedLosses() external view returns (uint256 unrealizedLosses_);
    function balanceOfAssets(address account_) external view returns (uint256 assets_);
    function convertToExitAssets(uint256 shares_) external view returns (uint256 assets_);
}
