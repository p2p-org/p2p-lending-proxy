// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./IP2pYieldProxy.sol";
import "./features/AccruedRewardsWithTreasury.sol";
import "./features/AdditionalRewardClaimer.sol";
import "./features/AnyFunctionWithCalldataChecker.sol";
import "./features/ProxyInitializer.sol";
import "./immutables/AllowedCalldataByClientToP2pCheckerImmutable.sol";
import "./immutables/FactoryImmutable.sol";
import "./interfaces/IDepositable.sol";

/// @title P2pYieldProxy
/// @notice P2pYieldProxy is a contract that allows a client to deposit and withdraw assets from a yield protocol.
abstract contract P2pYieldProxy is
    ERC165,
    IDepositable,
    FactoryImmutable,
    AccruedRewardsWithTreasury,
    AnyFunctionWithCalldataChecker,
    AdditionalRewardClaimer,
    AllowedCalldataByClientToP2pCheckerImmutable,
    ProxyInitializer
{
    /// @notice Constructor for P2pYieldProxy
    /// @param _factoryAddress The factory address
    /// @param _p2pTreasuryAddress_ The P2pTreasury address
    /// @param _allowedCalldataCheckerAddress AllowedCalldataChecker (p2pOperator-controlled, for client calls)
    /// @param _allowedCalldataByClientToP2pCheckerAddress AllowedCalldataChecker (client-controlled, for p2pOperator calls)
    constructor(
        address _factoryAddress,
        address _p2pTreasuryAddress_,
        address _allowedCalldataCheckerAddress,
        address _allowedCalldataByClientToP2pCheckerAddress
    )
        FactoryImmutable(_factoryAddress)
        AccruedRewardsWithTreasury(_p2pTreasuryAddress_)
        AnyFunctionWithCalldataChecker(_allowedCalldataCheckerAddress)
        AllowedCalldataByClientToP2pCheckerImmutable(_allowedCalldataByClientToP2pCheckerAddress)
    {}

    /// @dev Resolves _allowedCalldataChecker diamond: AdditionalRewardClaimer (abstract) + AnyFunctionWithCalldataChecker (concrete)
    function _allowedCalldataChecker()
        internal
        view
        virtual
        override(AdditionalRewardClaimer, AnyFunctionWithCalldataChecker)
        returns (IAllowedCalldataChecker)
    {
        return AnyFunctionWithCalldataChecker._allowedCalldataChecker();
    }

    /// @dev Resolves _allowedCalldataByClientToP2pChecker diamond: AdditionalRewardClaimer (abstract) + AllowedCalldataByClientToP2pCheckerImmutable (concrete)
    function _allowedCalldataByClientToP2pChecker()
        internal
        view
        virtual
        override(AdditionalRewardClaimer, AllowedCalldataByClientToP2pCheckerImmutable)
        returns (IAllowedCalldataChecker)
    {
        return AllowedCalldataByClientToP2pCheckerImmutable._allowedCalldataByClientToP2pChecker();
    }

    /// @dev Resolves _distributeWithFeeBase diamond: AdditionalRewardClaimer (abstract) + Withdrawable (concrete)
    function _distributeWithFeeBase(
        address _asset,
        uint256 _totalAmount,
        uint256 _feeBaseAmount
    )
        internal
        virtual
        override(AdditionalRewardClaimer, Withdrawable)
        returns (uint256 p2pAmount, uint256 clientAmount)
    {
        return Withdrawable._distributeWithFeeBase(_asset, _totalAmount, _feeBaseAmount);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IP2pYieldProxy).interfaceId || super.supportsInterface(interfaceId);
    }
}
