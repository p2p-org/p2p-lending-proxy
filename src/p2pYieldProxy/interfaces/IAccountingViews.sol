// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IAccountingViews {
    function getTotalDeposited(address _asset) external view returns (uint256);
    function getTotalWithdrawn(address _asset) external view returns (uint256);
    function getUserPrincipal(address _asset) external view returns (uint256);
    function calculateAccruedRewards(address _yieldProtocolAddress, address _asset) external view returns (int256);
    function getLastFeeCollectionTime(address _asset) external view returns (uint48);
}

