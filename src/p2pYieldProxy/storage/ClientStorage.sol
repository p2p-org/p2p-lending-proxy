// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

abstract contract ClientStorage {
    address internal s_client;

    function getClient() public view virtual returns (address) {
        return s_client;
    }
}
