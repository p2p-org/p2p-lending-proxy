// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../storage/ClientStorage.sol";
import "../P2pYieldProxyErrors.sol";

abstract contract ClientCallable is ClientStorage {
    modifier onlyClient() {
        if (msg.sender != s_client) {
            revert P2pYieldProxy__NotClientCalled(msg.sender, s_client);
        }
        _;
    }
}
