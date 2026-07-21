// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";

error P2pYieldProxy__ZeroAddressAsset();
error P2pYieldProxy__ZeroAssetAmount();
error P2pYieldProxy__ZeroSharesAmount();
error P2pYieldProxy__InvalidClientBasisPoints(uint96 _clientBasisPoints);
error P2pYieldProxy__NotFactory(address _factory);
error P2pYieldProxy__DifferentActuallyDepositedAmount(
    uint256 _requestedAmount,
    uint256 _actualAmount
);
error P2pYieldProxy__AmountExceedsAccrued(uint256 _withdrawn, uint256 _maxAllowed);
error P2pYieldProxy__NotFactoryCalled(
    address _msgSender,
    IP2pYieldProxyFactory _actualFactory
);
error P2pYieldProxy__NotClientCalled(
    address _msgSender,
    address _actualClient
);
error P2pYieldProxy__ZeroAddressFactory();
error P2pYieldProxy__ZeroAddressP2pTreasury();
error P2pYieldProxy__ZeroAllowedCalldataChecker();
error P2pYieldProxy__ZeroAllowedCalldataByClientToP2pChecker();
error P2pYieldProxy__CallerNeitherClientNorP2pOperator(address _caller);
error P2pYieldProxy__DataTooShort();
