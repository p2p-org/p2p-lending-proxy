// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryGetP2pSigner {
    function getP2pSigner() external view returns (address signer);
}
