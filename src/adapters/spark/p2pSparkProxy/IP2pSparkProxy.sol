// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IP2pSparkProxy {
    /// @notice Withdraws from SparkLend. Only callable by client.
    /// @param _asset The underlying asset address.
    /// @param _amount Amount to withdraw (use type(uint256).max for all).
    function withdraw(address _asset, uint256 _amount) external;

    /// @notice Withdraws only the accrued rewards portion. Only callable by P2P operator.
    /// @param _asset The underlying asset address.
    function withdrawAccruedRewards(address _asset) external;

    /// @notice Returns the SparkLend Pool address.
    function getSparkPool() external view returns (address);

    /// @notice Returns the SparkLend ProtocolDataProvider address.
    function getSparkDataProvider() external view returns (address);

    /// @notice Returns the spToken address for a given asset.
    function getSpToken(address _asset) external view returns (address);
}
