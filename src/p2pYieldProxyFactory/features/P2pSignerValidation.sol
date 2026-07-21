// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "../../@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../P2pYieldProxyFactoryErrors.sol";
import "../storage/P2pSignerStorage.sol";
import "./P2pSignerHashing.sol";

abstract contract P2pSignerValidation is P2pSignerStorage, P2pSignerHashing {
    using SignatureChecker for address;
    using ECDSA for bytes32;

    modifier p2pSignerSignatureShouldNotExpire(uint256 _p2pSignerSigDeadline) {
        require(
            block.timestamp < _p2pSignerSigDeadline,
            P2pYieldProxyFactory__P2pSignerSignatureExpired(_p2pSignerSigDeadline)
        );
        _;
    }

    modifier p2pSignerSignatureShouldBeValid(
        address _referenceP2pYieldProxy,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    ) {
        require(
            s_p2pSigner.isValidSignatureNow(
                getHashForP2pSigner(
                    _referenceP2pYieldProxy,
                    msg.sender,
                    _clientBasisPoints,
                    _p2pSignerSigDeadline
                )
                    .toEthSignedMessageHash(),
                _p2pSignerSignature
            ),
            P2pYieldProxyFactory__InvalidP2pSignerSignature()
        );
        _;
    }
}
