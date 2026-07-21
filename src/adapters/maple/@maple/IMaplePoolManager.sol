// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Maple PoolManager (needed for withdrawal queue processing).
interface IMaplePoolManager {
    function pool() external view returns (address);
    function withdrawalManager() external view returns (address);
    function poolPermissionManager() external view returns (address);
    function totalAssets() external view returns (uint256 totalAssets_);
    function poolDelegate() external view returns (address);
    function processRedeem(uint256 shares_, address owner_, address sender_) external returns (uint256 redeemableShares_, uint256 resultingAssets_);
}
