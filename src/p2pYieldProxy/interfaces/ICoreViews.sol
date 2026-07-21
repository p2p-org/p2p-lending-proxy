// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface ICoreViews {
    function getFactory() external view returns (address);
    function getP2pTreasury() external view returns (address);
    function getClient() external view returns (address);
    function getClientBasisPoints() external view returns (uint96);
}

