// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryTransferP2pSigner {
    function transferP2pSigner(address _newP2pSigner) external;
}
