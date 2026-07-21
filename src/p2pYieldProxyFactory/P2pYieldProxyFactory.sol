// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../access/P2pOperator2Step.sol";
import "../common/AllowedCalldataChecker.sol";
import "./IP2pYieldProxyFactory.sol";
import "./features/FactoryDepositExecutor.sol";
import "./features/P2pSignerTransferable.sol";
import "./features/P2pSignerHashing.sol";
import "./features/DeterministicProxyCreation.sol";
import "./features/ReferenceP2pYieldProxyAllowlist.sol";
import "./storage/P2pSignerStorage.sol";
import "./storage/AllProxiesStorage.sol";
import "./storage/ReferenceP2pYieldProxiesStorage.sol";

/// @title P2pYieldProxyFactory
/// @author P2P Validator <info@p2p.org>
/// @notice P2pYieldProxyFactory is a factory contract for creating P2pYieldProxy contracts
contract P2pYieldProxyFactory is
    AllowedCalldataChecker,
    P2pOperator2Step,
    ERC165,
    FactoryDepositExecutor,
    ReferenceP2pYieldProxyAllowlist,
    P2pSignerTransferable
{
    /// @notice Constructor for P2pYieldProxyFactory
    /// @param _p2pSigner The P2pSigner address
    constructor(address _p2pSigner) P2pOperator(msg.sender) {
        _setP2pSigner(_p2pSigner);
    }

    function _authorizeP2pSignerTransfer() internal view virtual override {
        _checkP2pOperator();
    }

    function _authorizeReferenceP2pYieldProxyAllowlist() internal view virtual override {
        _checkP2pOperator();
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IP2pYieldProxyFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
