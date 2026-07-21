// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../../p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "../p2pSuperformProxy/P2pSuperformProxy.sol";
import "./IP2pSuperformProxyFactory.sol";
import {IERC4626} from "../../../@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Entry point for depositing into Superform with P2P.org
contract P2pSuperformProxyFactory is P2pYieldProxyFactory, IP2pSuperformProxyFactory {
    /// @notice Constructor for P2pSuperformProxyFactory
    /// @param _p2pSigner The P2pSigner address
    /// @param _p2pOperator The P2pOperator address
    /// @param _p2pTreasury The P2pTreasury address
    /// @param _superformRouter SuperformRouter address
    /// @param _superPositions SuperPositions address
    /// @param _allowedCalldataChecker AllowedCalldataChecker
    /// @param _rewardsDistributor RewardsDistributor
    constructor(
        address _p2pSigner,
        address _p2pOperator,
        address _p2pTreasury,
        address _superformRouter,
        address _superPositions,
        address _allowedCalldataChecker,
        address _rewardsDistributor
    ) P2pYieldProxyFactory(_p2pSigner, _p2pOperator) {
        i_referenceP2pYieldProxy = new P2pSuperformProxy(
            address(this), _p2pTreasury, _superformRouter, _superPositions, _allowedCalldataChecker, _rewardsDistributor
        );
    }

    /// @dev Checks if the claim is valid
    /// @param _p2pOperatorToCheck The P2pOperator to check
    function checkClaim(address _p2pOperatorToCheck) public view {
        require(getP2pOperator() == _p2pOperatorToCheck, P2pOperator__UnauthorizedAccount(_p2pOperatorToCheck));
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function transferP2pOperator(address _newP2pOperator)
        public
        override(P2pYieldProxyFactory, IP2pYieldProxyFactory)
    {
        P2pYieldProxyFactory.transferP2pOperator(_newP2pOperator);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function acceptP2pOperator() public override(P2pYieldProxyFactory, IP2pYieldProxyFactory) {
        P2pYieldProxyFactory.acceptP2pOperator();
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getPendingP2pOperator()
        public
        view
        override(P2pYieldProxyFactory, IP2pYieldProxyFactory)
        returns (address)
    {
        return P2pYieldProxyFactory.getPendingP2pOperator();
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxyFactory, IERC165)
        returns (bool)
    {
        return interfaceId == type(IP2pSuperformProxyFactory).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getP2pOperator() public view override(P2pYieldProxyFactory, IP2pYieldProxyFactory) returns (address) {
        return P2pYieldProxyFactory.getP2pOperator();
    }
}
