// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Spark Rewards (merkle-based distribution).
/// Used by SparkRewards, Ignition Rewards, and PFL3 Rewards contracts.
interface ISparkRewards {
    function claim(
        uint256 epoch,
        address account,
        address token,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external returns (uint256 claimedAmount);

    function merkleRoot() external view returns (bytes32);

    function wallet() external view returns (address);

    function epochClosed(uint256 epoch) external view returns (bool);

    function cumulativeClaimed(address account, address token, uint256 epoch) external view returns (uint256);
}
