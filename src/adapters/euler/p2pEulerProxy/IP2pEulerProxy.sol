// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IP2pEulerProxy {
    /// @notice Emitted when reward streams rewards are claimed and distributed.
    event P2pEulerProxy__ClaimedRewardStreams(
        address indexed vault,
        address indexed reward,
        uint256 totalClaimed,
        uint256 p2pAmount,
        uint256 clientAmount
    );

    /// @notice Withdraws from an Euler EVault. Only callable by client.
    /// @param _vault The EVault address.
    /// @param _shares Amount of eToken shares to redeem.
    function withdraw(address _vault, uint256 _shares) external;

    /// @notice Withdraws only the accrued yield portion. Only callable by P2P operator.
    /// @param _vault The EVault address.
    function withdrawAccruedRewards(address _vault) external;

    /// @notice Claims reward tokens from Euler Reward Streams and distributes with fee.
    /// @param _vault The EVault address (rewarded token).
    /// @param _reward The reward token address.
    function claimRewardStreams(address _vault, address _reward) external;

    /// @notice Enables balance forwarding on the EVault so the proxy accrues Reward Streams rewards.
    /// @param _vault The EVault address.
    function enableBalanceForwarder(address _vault) external;

    /// @notice Enables a specific reward token on Reward Streams for the proxy.
    /// @param _vault The EVault address (rewarded token).
    /// @param _reward The reward token address.
    function enableReward(address _vault, address _reward) external;
}
