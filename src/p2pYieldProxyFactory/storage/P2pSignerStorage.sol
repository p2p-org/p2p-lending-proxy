// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../interfaces/IFactoryGetP2pSigner.sol";

abstract contract P2pSignerStorage is IFactoryGetP2pSigner {
    address internal s_p2pSigner;

    function getP2pSigner() public view virtual override(IFactoryGetP2pSigner) returns (address) {
        return s_p2pSigner;
    }
}
