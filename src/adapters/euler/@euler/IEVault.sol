// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Euler EVault (ERC-4626 lending vault).
/// Deposits/withdrawals MUST go through the EVC (Ethereum Vault Connector).
interface IEVault {
    // ERC-4626
    function deposit(uint256 amount, address receiver) external returns (uint256 shares);
    function redeem(uint256 amount, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256 shares);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function balanceOf(address account) external view returns (uint256);
    function maxDeposit(address account) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);

    // Balance Forwarder (for reward tracking)
    function balanceTrackerAddress() external view returns (address);
    function balanceForwarderEnabled(address account) external view returns (bool);
    function enableBalanceForwarder() external;
    function disableBalanceForwarder() external;
}
