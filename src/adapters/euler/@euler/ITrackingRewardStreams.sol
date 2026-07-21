// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Euler TrackingRewardStreams (Balance Tracker / Reward Streams).
/// Allows users to enable/disable/claim reward tokens for any EVault.
interface ITrackingRewardStreams {
    /// @notice Enable a reward token for the caller on the given rewarded vault.
    /// @param rewarded The EVault address (rewarded token).
    /// @param reward The reward token address (e.g. EUL).
    /// @return Whether the reward was newly enabled.
    function enableReward(address rewarded, address reward) external returns (bool);

    /// @notice Disable a reward token for the caller on the given rewarded vault.
    /// @param rewarded The EVault address (rewarded token).
    /// @param reward The reward token address.
    /// @param forfeitRecentReward Whether to forfeit the most recent epoch's reward.
    /// @return Whether the reward was disabled.
    function disableReward(address rewarded, address reward, bool forfeitRecentReward) external returns (bool);

    /// @notice Claim accumulated rewards.
    /// @param rewarded The EVault address (rewarded token).
    /// @param reward The reward token address.
    /// @param recipient Address to receive the reward tokens (address(0) = just update, no transfer).
    /// @param ignoreRecentReward Whether to ignore the most recent epoch's reward.
    /// @return The amount of reward tokens claimed.
    function claimReward(address rewarded, address reward, address recipient, bool ignoreRecentReward)
        external
        returns (uint256);

    /// @notice Query earned (claimable) rewards for an account.
    /// @param account The account to query.
    /// @param rewarded The EVault address.
    /// @param reward The reward token address.
    /// @param ignoreRecentReward Whether to ignore the most recent epoch.
    /// @return The claimable reward amount.
    function earnedReward(address account, address rewarded, address reward, bool ignoreRecentReward)
        external
        view
        returns (uint256);

    /// @notice Get the list of enabled reward tokens for an account on a vault.
    /// @param account The account to query.
    /// @param rewarded The EVault address.
    /// @return Array of enabled reward token addresses.
    function enabledRewards(address account, address rewarded) external view returns (address[] memory);

    /// @notice Get the account's tracked balance for a rewarded vault.
    function balanceOf(address account, address rewarded) external view returns (uint256);
}
