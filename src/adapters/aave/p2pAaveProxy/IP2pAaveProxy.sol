// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/IP2pYieldProxy.sol";

interface IP2pAaveProxy is IP2pYieldProxy {
    function deposit(address _asset, uint256 _amount) external override;

    function withdraw(address _asset, uint256 _amount) external;

    function withdrawAccruedRewards(address _asset) external;

    function getAavePool() external view returns (address);

    function getAaveDataProvider() external view returns (address);

    function getAToken(address _asset) external view returns (address);
}
