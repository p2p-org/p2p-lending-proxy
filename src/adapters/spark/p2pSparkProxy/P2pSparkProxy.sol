// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../aave/p2pAaveLikeProxy/P2pAaveLikeProxy.sol";
import "./IP2pSparkProxy.sol";

error P2pSparkProxy__ZeroAddressAsset();
error P2pSparkProxy__NotP2pOperator(address _caller);
error P2pSparkProxy__ZeroAccruedRewards();

/// @title P2pSparkProxy
/// @notice P2P Yield Proxy adapter for SparkLend (Aave V3 fork).
/// Inherits all deposit/withdraw/accrual logic from P2pAaveLikeProxy.
contract P2pSparkProxy is P2pAaveLikeProxy, IP2pSparkProxy {

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker,
        address _sparkPool,
        address _sparkDataProvider
    ) P2pAaveLikeProxy(
        _factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker,
        _sparkPool, _sparkDataProvider
    ) {}

    function deposit(address _asset, uint256 _amount) external override {
        require(_asset != address(0), P2pSparkProxy__ZeroAddressAsset());
        _depositToPool(_asset, _amount);
    }

    function withdraw(address _asset, uint256 _amount) external override onlyClient {
        require(_asset != address(0), P2pSparkProxy__ZeroAddressAsset());
        _withdrawFromPool(_asset, _amount);
    }

    function withdrawAccruedRewards(address _asset) external override onlyP2pOperator {
        require(_asset != address(0), P2pSparkProxy__ZeroAddressAsset());
        int256 accrued = _getAccruedRewards(_asset);
        require(accrued > 0, P2pSparkProxy__ZeroAccruedRewards());
        _withdrawAccruedFromPool(_asset, accrued);
    }

    function getSparkPool() external view override returns (address) {
        return address(i_pool);
    }

    function getSparkDataProvider() external view override returns (address) {
        return address(i_dataProvider);
    }

    function getSpToken(address _asset) public view override returns (address) {
        return getYieldToken(_asset);
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pSparkProxy__NotP2pOperator(_caller);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pSparkProxy).interfaceId || super.supportsInterface(interfaceId);
    }
}
