// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@compound/IComet.sol";
import "../@compound/ICometRewards.sol";
import "../CompoundMarketRegistry.sol";
import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "./IP2pCompoundProxy.sol";

error P2pCompoundProxy__ZeroAddressAsset();
error P2pCompoundProxy__NotP2pOperator(address _caller);
error P2pCompoundProxy__ZeroAccruedRewards();
error P2pCompoundProxy__ZeroCometRewards();
error P2pCompoundProxy__ZeroMarketRegistry();

contract P2pCompoundProxy is P2pYieldProxy, IP2pCompoundProxy {
    CompoundMarketRegistry private immutable i_marketRegistry;
    ICometRewards private immutable i_cometRewards;

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker,
        address _marketRegistry,
        address _cometRewards
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker) {
        require(_marketRegistry != address(0), P2pCompoundProxy__ZeroMarketRegistry());
        require(_cometRewards != address(0), P2pCompoundProxy__ZeroCometRewards());
        i_marketRegistry = CompoundMarketRegistry(_marketRegistry);
        i_cometRewards = ICometRewards(_cometRewards);
    }

    function deposit(address _asset, uint256 _amount) external override {
        require(_asset != address(0), P2pCompoundProxy__ZeroAddressAsset());
        address comet = _getComet(_asset);
        bytes memory supplyCalldata = abi.encodeCall(IComet.supply, (_asset, _amount));
        _deposit(comet, comet, supplyCalldata, _asset, _amount, false);
    }

    function withdraw(address _asset, uint256 _amount) external override onlyClient {
        require(_asset != address(0), P2pCompoundProxy__ZeroAddressAsset());
        address comet = _getComet(_asset);

        uint256 actualAmount = _amount;
        if (_amount == type(uint256).max) {
            actualAmount = IComet(comet).balanceOf(address(this));
        }

        bytes memory withdrawCalldata = abi.encodeCall(IComet.withdraw, (_asset, actualAmount));
        _withdraw(comet, _asset, comet, withdrawCalldata, 0);
    }

    function withdrawAccruedRewards(address _asset) external override onlyP2pOperator {
        require(_asset != address(0), P2pCompoundProxy__ZeroAddressAsset());
        address comet = _getComet(_asset);

        int256 accruedBefore = calculateAccruedRewards(comet, _asset);
        require(accruedBefore > 0, P2pCompoundProxy__ZeroAccruedRewards());

        bytes memory withdrawCalldata =
            abi.encodeCall(IComet.withdraw, (_asset, uint256(accruedBefore)));
        uint256 withdrawn = _withdraw(comet, _asset, comet, withdrawCalldata, 0);
        _requireWithdrawnWithinAccrued(withdrawn, accruedBefore, 0);
    }

    function calculateAccruedRewards(address, address _asset)
        public
        view
        override
        returns (int256)
    {
        address comet = _getComet(_asset);
        uint256 currentAmount = IComet(comet).balanceOf(address(this));
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function getComet(address _asset) external view override returns (address) {
        return _getComet(_asset);
    }

    function getMarketRegistry() external view override returns (address) {
        return address(i_marketRegistry);
    }

    function getCometRewards() external view override returns (address) {
        return address(i_cometRewards);
    }

    function _getP2pOperator() internal view override returns (address) {
        return i_factory.getP2pOperator();
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pCompoundProxy__NotP2pOperator(_caller);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pCompoundProxy).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getComet(address _asset) private view returns (address) {
        return i_marketRegistry.getComet(_asset);
    }
}
