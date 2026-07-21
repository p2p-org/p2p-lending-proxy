// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryGetAllProxies {
    function getAllProxies() external view returns (address[] memory proxies);
}
