// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../p2pYieldProxy/P2pYieldProxy.sol";
import "../IP2pYieldProxyFactory.sol";
import "../interfaces/IFactoryDeposit.sol";
import "./DeterministicProxyCreation.sol";
import "./P2pSignerValidation.sol";

abstract contract FactoryDepositExecutor is IFactoryDeposit, DeterministicProxyCreation, P2pSignerValidation {
    function deposit(
        address _referenceP2pYieldProxy,
        address _asset,
        uint256 _amount,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    )
        public
        virtual
        override(IFactoryDeposit)
        p2pSignerSignatureShouldNotExpire(_p2pSignerSigDeadline)
        p2pSignerSignatureShouldBeValid(
            _referenceP2pYieldProxy,
            _clientBasisPoints,
            _p2pSignerSigDeadline,
            _p2pSignerSignature
        )
        returns (address p2pYieldProxyAddress)
    {
        P2pYieldProxy p2pYieldProxy = _getOrCreateP2pYieldProxy(_referenceP2pYieldProxy, _clientBasisPoints);
        p2pYieldProxy.deposit(_asset, _amount);

        emit IP2pYieldProxyFactory.P2pYieldProxyFactory__Deposited(msg.sender, _clientBasisPoints);
        return address(p2pYieldProxy);
    }
}
