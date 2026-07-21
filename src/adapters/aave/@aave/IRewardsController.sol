// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title IRewardsController
/// @notice Minimal interface for Aave V3 RewardsController and Umbrella RewardsController
interface IRewardsController {
    /// @notice Claims all accrued rewards for msg.sender across listed assets
    /// @param assets The list of aToken / staked asset addresses to claim for
    /// @return rewardsList The addresses of each reward token claimed
    /// @return claimedAmounts The amounts of each reward token claimed
    function claimAllRewardsToSelf(address[] calldata assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /// @notice Claims accrued rewards for a specific reward token
    /// @param assets The list of aToken / staked asset addresses
    /// @param amount The amount of reward to claim
    /// @param to The recipient of the claimed rewards
    /// @param reward The reward token address
    /// @return The amount actually claimed
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);

    /// @notice Claims all accrued rewards for all reward tokens
    /// @param assets The list of aToken / staked asset addresses
    /// @param to The recipient of the claimed rewards
    /// @return rewardsList The addresses of each reward token claimed
    /// @return claimedAmounts The amounts of each reward token claimed
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
