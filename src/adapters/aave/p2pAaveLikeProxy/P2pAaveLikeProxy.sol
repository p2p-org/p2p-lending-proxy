// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../aave/@aave/IAaveProtocolDataProvider.sol";
import "../../aave/@aave/IAaveV3Pool.sol";
import "../../../p2pYieldProxy/P2pYieldProxy.sol";

error P2pAaveLikeProxy__AssetNotSupported(address _asset);

/// @title P2pAaveLikeProxy
/// @notice Abstract base for Aave V3 and its forks (SparkLend).
///   Deposit: pool.supply(asset, amount, proxy, 0) → proxy receives yield-bearing token.
///   Withdrawal: pool.withdraw(asset, amount, proxy) — instant.
///   Accounting: yield-bearing token balance is 1:1 with principal + accrued yield.
abstract contract P2pAaveLikeProxy is P2pYieldProxy {
    IAaveV3Pool internal immutable i_pool;
    IAaveProtocolDataProvider internal immutable i_dataProvider;

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker,
        address _pool,
        address _dataProvider
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker) {
        require(_pool != address(0));
        require(_dataProvider != address(0));
        i_pool = IAaveV3Pool(_pool);
        i_dataProvider = IAaveProtocolDataProvider(_dataProvider);
    }

    function _depositToPool(address _asset, uint256 _amount) internal {
        address yieldToken = getYieldToken(_asset);
        bytes memory supplyCalldata = abi.encodeCall(IAaveV3Pool.supply, (_asset, _amount, address(this), 0));
        _deposit(yieldToken, address(i_pool), supplyCalldata, _asset, _amount, false);
    }

    function _withdrawFromPool(address _asset, uint256 _amount) internal {
        address yieldToken = getYieldToken(_asset);
        bytes memory withdrawCalldata = abi.encodeCall(IAaveV3Pool.withdraw, (_asset, _amount, address(this)));
        _withdraw(yieldToken, _asset, address(i_pool), withdrawCalldata, 0);
    }

    /// @dev Withdraws accrued rewards. Caller MUST check accruedBefore > 0 with its own error.
    function _withdrawAccruedFromPool(address _asset, int256 _accruedBefore) internal returns (uint256) {
        address yieldToken = getYieldToken(_asset);

        bytes memory withdrawCalldata =
            abi.encodeCall(IAaveV3Pool.withdraw, (_asset, uint256(_accruedBefore), address(this)));
        uint256 withdrawn = _withdraw(yieldToken, _asset, address(i_pool), withdrawCalldata, 0);
        _requireWithdrawnWithinAccrued(withdrawn, _accruedBefore, 0);
        return withdrawn;
    }

    function _getAccruedRewards(address _asset) internal view returns (int256) {
        address yieldToken = getYieldToken(_asset);
        return calculateAccruedRewards(yieldToken, _asset);
    }

    function calculateAccruedRewards(address, address _asset)
        public
        view
        override
        returns (int256)
    {
        address yieldToken = getYieldToken(_asset);
        uint256 currentAmount = IERC20(yieldToken).balanceOf(address(this));
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function getYieldToken(address _asset) public view returns (address) {
        try i_dataProvider.getReserveTokensAddresses(_asset) returns (address yieldToken, address, address) {
            require(yieldToken != address(0), P2pAaveLikeProxy__AssetNotSupported(_asset));
            return yieldToken;
        } catch {
            revert P2pAaveLikeProxy__AssetNotSupported(_asset);
        }
    }

    function _getP2pOperator() internal view override returns (address) {
        return i_factory.getP2pOperator();
    }
}
