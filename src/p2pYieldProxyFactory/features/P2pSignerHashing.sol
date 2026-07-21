// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../interfaces/IFactoryGetHashForP2pSigner.sol";

abstract contract P2pSignerHashing is IFactoryGetHashForP2pSigner {
    function getHashForP2pSigner(
        address _referenceP2pYieldProxy,
        address _client,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline
    ) public view virtual override(IFactoryGetHashForP2pSigner) returns (bytes32) {
        return keccak256(
            abi.encode(
                _referenceP2pYieldProxy,
                _client,
                _clientBasisPoints,
                _p2pSignerSigDeadline,
                address(this),
                block.chainid
            )
        );
    }
}
