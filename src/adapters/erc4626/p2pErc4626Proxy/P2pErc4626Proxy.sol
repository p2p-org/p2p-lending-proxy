// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../../../p2pYieldProxy/interfaces/IDepositable.sol";
import "../../../@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./IP2pErc4626Proxy.sol";

error P2pErc4626Proxy__ZeroVaultAddress();
error P2pErc4626Proxy__NotP2pOperator(address _caller);
error P2pErc4626Proxy__ZeroAccruedRewards();

/// @title P2pErc4626Proxy
/// @notice Generic P2P Yield Proxy adapter for any standard ERC-4626 vault.
///
/// Works with any vault that implements the standard ERC-4626 interface:
///   - deposit(assets, receiver) for deposits
///   - redeem(shares, receiver, owner) for withdrawals
///   - convertToAssets(shares) for yield tracking
///
/// Confirmed compatible protocols:
///   - Fluid fTokens (fUSDC, fUSDT, fWETH)
///   - MetaMorpho vaults (Steakhouse, Gauntlet, etc.) — direct deposit, no bundler needed
///   - Any other standard ERC-4626 vault
///
/// Protocol-specific reward claiming (e.g. Morpho URD/Merkl) is handled via the
/// existing claimAdditionalRewardTokens + AllowedCalldataChecker mechanism.
contract P2pErc4626Proxy is P2pYieldProxy, IP2pErc4626Proxy {
    using SafeERC20 for IERC20;

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _allowedCalldataByClientToP2pChecker
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker, _allowedCalldataByClientToP2pChecker) {}

    /// @notice Deposits into an ERC-4626 vault.
    /// The factory calls deposit(_vault, _amount) where _vault is the vault address.
    /// The underlying asset is resolved from IERC4626(_vault).asset().
    /// @param _vault The ERC-4626 vault address.
    /// @param _amount Amount of the underlying asset to deposit.
    function deposit(address _vault, uint256 _amount) external override(IDepositable) {
        require(_vault != address(0), P2pErc4626Proxy__ZeroVaultAddress());
        address asset = IERC4626(_vault).asset();
        bytes memory depositCalldata = abi.encodeCall(IERC4626.deposit, (_amount, address(this)));
        // _vault is both the accounting target and call target
        // _transferBeforeCall=false: proxy approves vault, vault pulls via transferFrom
        _deposit(_vault, _vault, depositCalldata, asset, _amount, false);
    }

    /// @inheritdoc IP2pErc4626Proxy
    function withdraw(address _vault, uint256 _shares) external override onlyClient {
        require(_vault != address(0), P2pErc4626Proxy__ZeroVaultAddress());
        address asset = IERC4626(_vault).asset();
        bytes memory redeemCalldata = abi.encodeCall(IERC4626.redeem, (_shares, address(this), address(this)));
        _withdraw(_vault, asset, _vault, redeemCalldata, _shares);
    }

    /// @inheritdoc IP2pErc4626Proxy
    function withdrawAccruedRewards(address _vault) external override onlyP2pOperator {
        require(_vault != address(0), P2pErc4626Proxy__ZeroVaultAddress());
        address asset = IERC4626(_vault).asset();

        int256 accruedBefore = calculateAccruedRewards(_vault, asset);
        require(accruedBefore > 0, P2pErc4626Proxy__ZeroAccruedRewards());

        uint256 shares = IERC4626(_vault).convertToShares(uint256(accruedBefore));
        bytes memory redeemCalldata = abi.encodeCall(IERC4626.redeem, (shares, address(this), address(this)));
        uint256 withdrawn = _withdraw(_vault, asset, _vault, redeemCalldata, shares);
        _requireWithdrawnWithinAccrued(withdrawn, accruedBefore, 1);
    }

    /// @notice Calculates accrued rewards as current vault assets minus tracked user principal.
    function calculateAccruedRewards(address _vault, address _asset)
        public
        view
        override
        returns (int256)
    {
        uint256 shares = IERC20(_vault).balanceOf(address(this));
        uint256 currentAmount = IERC4626(_vault).convertToAssets(shares);
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
        return interfaceId == type(IP2pErc4626Proxy).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getP2pOperator() internal view override returns (address) {
        return i_factory.getP2pOperator();
    }

    function _revertNotP2pOperator(address _caller) internal pure override {
        revert P2pErc4626Proxy__NotP2pOperator(_caller);
    }
}
