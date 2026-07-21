// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Fluid fToken (ERC-4626 lending vault).
interface IFToken {
    // ERC-4626
    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);
    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);
    function withdraw(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares_) external view returns (uint256 assets_);
    function convertToShares(uint256 assets_) external view returns (uint256 shares_);
    function previewWithdraw(uint256 assets_) external view returns (uint256 shares_);
    function previewRedeem(uint256 shares_) external view returns (uint256 assets_);
    function balanceOf(address account_) external view returns (uint256);
    function maxDeposit(address receiver_) external view returns (uint256);
    function maxRedeem(address owner_) external view returns (uint256);

    // Fluid-specific
    function getData()
        external
        view
        returns (
            address liquidity_,
            address lendingFactory_,
            address lendingRewardsRateModel_,
            address permit2_,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            uint256 liquidityExchangePrice_,
            uint256 tokenExchangePrice_
        );

    function minDeposit() external view returns (uint256);
    function updateRates() external returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_);
}
