// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../p2pAaveLikeProxy/P2pAaveLikeProxy.sol";
import "./IP2pAaveProxy.sol";

error P2pAaveProxy__ZeroAddressAsset();
error P2pAaveProxy__NotP2pOperator(address _caller);
error P2pAaveProxy__ZeroAccruedRewards();

contract P2pAaveProxy is P2pAaveLikeProxy, IP2pAaveProxy {

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker,
        address _aavePool,
        address _aaveDataProvider
    ) P2pAaveLikeProxy(
        _factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker,
        _aavePool, _aaveDataProvider
    ) {}

    function deposit(address _asset, uint256 _amount) external override {
        require(_asset != address(0), P2pAaveProxy__ZeroAddressAsset());
        _depositToPool(_asset, _amount);
    }

    function withdraw(address _asset, uint256 _amount) external override onlyClient {
        require(_asset != address(0), P2pAaveProxy__ZeroAddressAsset());
        _withdrawFromPool(_asset, _amount);
    }

    function withdrawAccruedRewards(address _asset) external override onlyP2pOperator {
        require(_asset != address(0), P2pAaveProxy__ZeroAddressAsset());
        int256 accrued = _getAccruedRewards(_asset);
        require(accrued > 0, P2pAaveProxy__ZeroAccruedRewards());
        _withdrawAccruedFromPool(_asset, accrued);
    }

    function getAavePool() external view override returns (address) {
        return address(i_pool);
    }

    function getAaveDataProvider() external view override returns (address) {
        return address(i_dataProvider);
    }

    function getAToken(address _asset) public view override returns (address) {
        return getYieldToken(_asset);
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pAaveProxy__NotP2pOperator(_caller);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pAaveProxy).interfaceId || super.supportsInterface(interfaceId);
    }
}
