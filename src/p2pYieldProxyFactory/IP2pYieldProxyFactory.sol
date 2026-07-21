// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../common/IAllowedCalldataChecker.sol";
import "./interfaces/IFactoryDeposit.sol";
import "./interfaces/IFactoryPredictProxyAddress.sol";
import "./interfaces/IFactoryTransferP2pSigner.sol";
import "./interfaces/IFactoryTransferP2pOperator.sol";
import "./interfaces/IFactoryAcceptP2pOperator.sol";
import "./interfaces/IFactoryGetHashForP2pSigner.sol";
import "./interfaces/IFactoryGetP2pSigner.sol";
import "./interfaces/IFactoryGetP2pOperator.sol";
import "./interfaces/IFactoryGetPendingP2pOperator.sol";
import "./interfaces/IFactoryGetAllProxies.sol";
import "./interfaces/IFactoryAddReferenceP2pYieldProxy.sol";
import "./interfaces/IFactoryIsReferenceP2pYieldProxyAllowed.sol";

/// @dev External interface of P2pYieldProxyFactory
interface IP2pYieldProxyFactory is
    IAllowedCalldataChecker,
    IERC165,
    IFactoryDeposit,
    IFactoryPredictProxyAddress,
    IFactoryGetAllProxies,
    IFactoryAddReferenceP2pYieldProxy,
    IFactoryIsReferenceP2pYieldProxyAllowed,
    IFactoryGetP2pSigner,
    IFactoryGetHashForP2pSigner,
    IFactoryTransferP2pSigner,
    IFactoryGetP2pOperator,
    IFactoryGetPendingP2pOperator,
    IFactoryTransferP2pOperator,
    IFactoryAcceptP2pOperator
{

    /// @dev Emitted when the P2pSigner is transferred
    event P2pYieldProxyFactory__P2pSignerTransferred(
        address indexed _previousP2pSigner,
        address indexed _newP2pSigner
    );

    /// @dev Emitted when the deposit is made
    event P2pYieldProxyFactory__Deposited(
        address indexed _client,
        uint96 indexed _clientBasisPoints
    );

    /// @dev Emitted when the a new proxy is created
    event P2pYieldProxyFactory__ProxyCreated(
        address _proxy,
        address _client,
        uint96 _clientBasisPoints
    );

    /// @dev Emitted when a reference proxy is allowlisted
    event P2pYieldProxyFactory__ReferenceP2pYieldProxyAllowed(address indexed _referenceP2pYieldProxy);
    // Functions are inherited from the composed interfaces.
}
