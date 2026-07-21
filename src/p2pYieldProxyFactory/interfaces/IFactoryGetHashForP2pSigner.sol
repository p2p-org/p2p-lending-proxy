// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IFactoryGetHashForP2pSigner {
    function getHashForP2pSigner(
        address _referenceP2pYieldProxy,
        address _client,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline
    )
        external
        view
        returns (bytes32 signerHash);
}
