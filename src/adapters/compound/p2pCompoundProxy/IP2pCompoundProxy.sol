// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IP2pCompoundProxy {
    function withdraw(address _asset, uint256 _amount) external;

    function withdrawAccruedRewards(address _asset) external;

    function getComet(address _asset) external view returns (address);

    function getMarketRegistry() external view returns (address);

    function getCometRewards() external view returns (address);
}
