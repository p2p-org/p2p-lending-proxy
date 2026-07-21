// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Maple WithdrawalManagerQueue.
interface IWithdrawalManagerQueue {
    function lockedShares(address owner_) external view returns (uint256 lockedShares_);
    function requestIds(address owner_) external view returns (uint128);
    function isManualWithdrawal(address owner_) external view returns (bool);
    function manualSharesAvailable(address owner_) external view returns (uint256);
    function pool() external view returns (address);
    function poolManager() external view returns (address);
    function processRedemptions(uint256 maxSharesToProcess_) external;
    function setManualWithdrawal(address owner_, bool isManual_) external;
}
