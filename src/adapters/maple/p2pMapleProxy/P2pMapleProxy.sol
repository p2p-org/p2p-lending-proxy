// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../../../p2pYieldProxy/interfaces/IDepositable.sol";
import "../@maple/IMaplePool.sol";
import "../@maple/IMaplePoolManager.sol";
import "../@maple/IWithdrawalManagerQueue.sol";
import "./IP2pMapleProxy.sol";

error P2pMapleProxy__ZeroPoolAddress();
error P2pMapleProxy__PoolAssetMismatch(address _pool);
error P2pMapleProxy__NotP2pOperator(address _caller);
error P2pMapleProxy__ZeroAccruedRewards();

/// @title P2pMapleProxy
/// @notice P2P Yield Proxy adapter for Maple Finance pools.
/// Maple pools are ERC-4626 vaults with a FIFO withdrawal queue.
/// Deposit: pool.deposit(amount, proxy) — standard ERC-4626.
/// Withdrawal: pool.requestRedeem(shares, proxy) → pool delegate processes → pool.redeem(shares, proxy, proxy).
contract P2pMapleProxy is P2pYieldProxy, IP2pMapleProxy {
    using SafeERC20 for IERC20;

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker) {}

    /// @notice Deposits into a Maple pool.
    /// The factory calls deposit(_pool, _amount) where _pool is the Maple pool address
    /// passed as the `_asset` parameter in the factory's deposit() call.
    /// The actual underlying asset is resolved from pool.asset().
    /// @param _pool The Maple pool address (passed by factory as `_asset`).
    /// @param _amount Amount of the underlying asset to deposit.
    function deposit(address _pool, uint256 _amount) external override(IDepositable) {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        address asset = IMaplePool(_pool).asset();
        bytes memory depositCalldata = abi.encodeCall(IMaplePool.deposit, (_amount, address(this)));
        _deposit(_pool, _pool, depositCalldata, asset, _amount, false);
    }

    /// @inheritdoc IP2pMapleProxy
    function withdraw(address _pool, uint256 _shares) external override onlyClient {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        address asset = IMaplePool(_pool).asset();
        bytes memory redeemCalldata = abi.encodeCall(IMaplePool.redeem, (_shares, address(this), address(this)));
        _withdraw(_pool, asset, _pool, redeemCalldata, _shares);
    }

    /// @inheritdoc IP2pMapleProxy
    function withdrawAccruedRewards(address _pool) external override onlyP2pOperator {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        address asset = IMaplePool(_pool).asset();

        // Use the shares already processed by the WM (manualSharesAvailable).
        // These were set during processRedemptions after requestRedeemAccruedRewards.
        uint256 shares = _getManualSharesAvailable(_pool);
        require(shares > 0, P2pMapleProxy__ZeroAccruedRewards());

        int256 accruedBefore = calculateAccruedRewards(_pool, asset);
        require(accruedBefore > 0, P2pMapleProxy__ZeroAccruedRewards());

        bytes memory redeemCalldata = abi.encodeCall(IMaplePool.redeem, (shares, address(this), address(this)));
        uint256 withdrawn = _withdraw(_pool, asset, _pool, redeemCalldata, shares);
        _requireWithdrawnWithinAccrued(withdrawn, accruedBefore, 1);
    }

    /// @inheritdoc IP2pMapleProxy
    function requestRedeem(address _pool, uint256 _shares) external override onlyClient returns (uint256 escrowedShares_) {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        escrowedShares_ = IMaplePool(_pool).requestRedeem(_shares, address(this));
        emit P2pMapleProxy__RedemptionRequested(_pool, _shares, escrowedShares_);
    }

    /// @inheritdoc IP2pMapleProxy
    function requestRedeemAccruedRewards(address _pool) external override onlyP2pOperator returns (uint256 escrowedShares_) {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        address asset = IMaplePool(_pool).asset();

        int256 accruedBefore = calculateAccruedRewards(_pool, asset);
        require(accruedBefore > 0, P2pMapleProxy__ZeroAccruedRewards());

        uint256 shares = IMaplePool(_pool).convertToShares(uint256(accruedBefore));
        escrowedShares_ = IMaplePool(_pool).requestRedeem(shares, address(this));
        emit P2pMapleProxy__RedemptionRequested(_pool, shares, escrowedShares_);
    }

    /// @inheritdoc IP2pMapleProxy
    function removeShares(address _pool, uint256 _shares) external override onlyClient returns (uint256 sharesReturned_) {
        require(_pool != address(0), P2pMapleProxy__ZeroPoolAddress());
        sharesReturned_ = IMaplePool(_pool).removeShares(_shares, address(this));
        emit P2pMapleProxy__SharesRemoved(_pool, sharesReturned_);
    }

    /// @notice Calculates accrued rewards as current pool assets minus tracked user principal.
    /// Includes shares available for manual redemption in the WM (set by processRedemptions).
    function calculateAccruedRewards(address _pool, address _asset)
        public
        view
        override
        returns (int256)
    {
        uint256 shares = IERC20(_pool).balanceOf(address(this));
        uint256 wmShares = _getManualSharesAvailable(_pool);
        uint256 currentAmount = IMaplePool(_pool).convertToAssets(shares + wmShares);
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function _getManualSharesAvailable(address _pool) internal view returns (uint256) {
        address wm = IMaplePoolManager(IMaplePool(_pool).manager()).withdrawalManager();
        return IWithdrawalManagerQueue(wm).lockedShares(address(this));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pMapleProxy).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getP2pOperator() internal view override returns (address) {
        return i_factory.getP2pOperator();
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pMapleProxy__NotP2pOperator(_caller);
    }
}
