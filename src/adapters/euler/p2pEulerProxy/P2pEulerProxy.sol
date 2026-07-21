// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../../../p2pYieldProxy/interfaces/IDepositable.sol";
import "../@euler/IEVault.sol";
import "../@euler/IEVC.sol";
import "../@euler/ITrackingRewardStreams.sol";
import "./IP2pEulerProxy.sol";

error P2pEulerProxy__ZeroVaultAddress();
error P2pEulerProxy__NotP2pOperator(address _caller);
error P2pEulerProxy__ZeroAccruedRewards();
error P2pEulerProxy__NothingClaimed();

/// @title P2pEulerProxy
/// @notice P2P Yield Proxy adapter for Euler V2 EVaults (ERC-4626 lending vaults).
///
/// Euler EVaults require all state-changing operations (deposit, withdraw, redeem) to be
/// routed through the Ethereum Vault Connector (EVC). The EVC authenticates the caller
/// and sets the on-behalf-of context so the vault knows which account is acting.
///
/// Reward Streams:
///   - EVaults have an optional BalanceForwarder that notifies a TrackingRewardStreams
///     contract on every balance change.
///   - Users must call enableBalanceForwarder() on the vault AND enableReward() on
///     the reward streams for each reward token they want to accrue.
///   - Rewards are claimed via claimReward() on the TrackingRewardStreams contract.
contract P2pEulerProxy is P2pYieldProxy, IP2pEulerProxy {
    using SafeERC20 for IERC20;

    IEVC private immutable i_evc;

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker,
        address _evc
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker) {
        i_evc = IEVC(_evc);
    }

    /// @notice Deposits into an Euler EVault via EVC.
    /// The factory calls deposit(_vault, _amount) where _vault is the EVault address.
    /// The actual underlying asset is resolved from IEVault(_vault).asset().
    ///
    /// Euler's pullAssets does transferFrom(proxy → vault), so the proxy must approve
    /// the vault (not EVC) for the underlying asset. We pre-approve the vault, then
    /// call EVC.call → EVault.deposit. The base _deposit approves the EVC (harmless),
    /// then calls EVC which routes to the vault.
    /// @param _vault The EVault address.
    /// @param _amount Amount of underlying asset to deposit.
    function deposit(address _vault, uint256 _amount) external override(IDepositable) {
        require(_vault != address(0), P2pEulerProxy__ZeroVaultAddress());
        address asset = IEVault(_vault).asset();

        // Pre-approve the vault for the underlying asset (Euler pulls from proxy directly)
        IERC20(asset).safeIncreaseAllowance(_vault, _amount);

        // Build the calldata for EVC.call → EVault.deposit
        bytes memory vaultDepositCalldata = abi.encodeCall(IEVault.deposit, (_amount, address(this)));
        bytes memory evcCalldata = abi.encodeCall(IEVC.call, (_vault, address(this), 0, vaultDepositCalldata));

        // _deposit with _transferBeforeCall=false additionally approves EVC (harmless no-op),
        // then calls EVC.call which routes to the vault's deposit function.
        _deposit(_vault, address(i_evc), evcCalldata, asset, _amount, false);
    }

    /// @inheritdoc IP2pEulerProxy
    function withdraw(address _vault, uint256 _shares) external override onlyClient {
        require(_vault != address(0), P2pEulerProxy__ZeroVaultAddress());
        address asset = IEVault(_vault).asset();

        // Build EVC.call → EVault.redeem(shares, proxy, proxy)
        bytes memory vaultRedeemCalldata =
            abi.encodeCall(IEVault.redeem, (_shares, address(this), address(this)));
        bytes memory evcCalldata = abi.encodeCall(IEVC.call, (_vault, address(this), 0, vaultRedeemCalldata));

        _withdraw(_vault, asset, address(i_evc), evcCalldata, _shares);
    }

    /// @inheritdoc IP2pEulerProxy
    function withdrawAccruedRewards(address _vault) external override onlyP2pOperator {
        require(_vault != address(0), P2pEulerProxy__ZeroVaultAddress());
        address asset = IEVault(_vault).asset();

        int256 accruedBefore = calculateAccruedRewards(_vault, asset);
        require(accruedBefore > 0, P2pEulerProxy__ZeroAccruedRewards());

        uint256 shares = IEVault(_vault).convertToShares(uint256(accruedBefore));

        bytes memory vaultRedeemCalldata =
            abi.encodeCall(IEVault.redeem, (shares, address(this), address(this)));
        bytes memory evcCalldata = abi.encodeCall(IEVC.call, (_vault, address(this), 0, vaultRedeemCalldata));

        uint256 withdrawn = _withdraw(_vault, asset, address(i_evc), evcCalldata, shares);
        _requireWithdrawnWithinAccrued(withdrawn, accruedBefore, 1);
    }

    /// @inheritdoc IP2pEulerProxy
    function claimRewardStreams(address _vault, address _reward) external override nonReentrant {
        require(_vault != address(0), P2pEulerProxy__ZeroVaultAddress());

        address balanceTracker = IEVault(_vault).balanceTrackerAddress();
        require(balanceTracker != address(0), P2pEulerProxy__ZeroVaultAddress());

        uint256 claimed = ITrackingRewardStreams(balanceTracker).claimReward(
            _vault, _reward, address(this), false
        );
        require(claimed > 0, P2pEulerProxy__NothingClaimed());

        (uint256 p2pAmount, uint256 clientAmount) = _distributeWithFeeBase(_reward, claimed, claimed);

        emit P2pEulerProxy__ClaimedRewardStreams(_vault, _reward, claimed, p2pAmount, clientAmount);
    }

    /// @inheritdoc IP2pEulerProxy
    function enableBalanceForwarder(address _vault) external override {
        _requireClientOrP2pOperator();
        IEVault(_vault).enableBalanceForwarder();
    }

    /// @inheritdoc IP2pEulerProxy
    function enableReward(address _vault, address _reward) external override {
        _requireClientOrP2pOperator();
        address balanceTracker = IEVault(_vault).balanceTrackerAddress();
        ITrackingRewardStreams(balanceTracker).enableReward(_vault, _reward);
    }

    /// @notice Calculates accrued rewards as current vault assets minus tracked user principal.
    function calculateAccruedRewards(address _vault, address _asset)
        public
        view
        override
        returns (int256)
    {
        uint256 shares = IERC20(_vault).balanceOf(address(this));
        uint256 currentAmount = IEVault(_vault).convertToAssets(shares);
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pEulerProxy).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getP2pOperator() internal view override returns (address) {
        return i_factory.getP2pOperator();
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pEulerProxy__NotP2pOperator(_caller);
    }

    function _requireClientOrP2pOperator() private view {
        require(
            msg.sender == s_client || msg.sender == _getP2pOperator(),
            P2pEulerProxy__NotP2pOperator(msg.sender)
        );
    }
}
