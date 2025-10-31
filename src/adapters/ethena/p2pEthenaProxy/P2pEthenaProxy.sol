// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../IStakedUSDe.sol";
import "./IP2pEthenaProxy.sol";
import {IERC4626} from "../../../@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "../../../@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error P2pEthenaProxy__InvalidDepositAsset(address asset);
error P2pEthenaProxy__UnsupportedAsset(address asset);
error P2pEthenaProxy__ZeroAddressUSDe();
error P2pEthenaProxy__ZeroAddressStakedUSDe();

/// @title Adapter for interacting with the Ethena staking vault through a client proxy
/// @notice Handles deposits, cooldown flows, and withdrawals while enforcing the P2P fee split.
contract P2pEthenaProxy is P2pYieldProxy, IP2pEthenaProxy {
    using SafeERC20 for IERC20;

    /// @dev Staked USDe (ERC-4626) vault address
    address internal immutable i_stakedUSDe;

    /// @dev USDe asset address
    address internal immutable i_USDe;

    /// @dev Tracks the total amount of assets currently in the cooldown queue.
    uint256 private s_assetsCoolingDown;

    /// @notice Constructor for P2pEthenaProxy
    /// @param _factory Factory address
    /// @param _p2pTreasury P2pTreasury address
    /// @param _allowedCalldataChecker AllowedCalldataChecker proxy address
    /// @param _stakedUSDe StakedUSDe (sUSDe) address
    /// @param _USDe USDe token address
    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _stakedUSDe,
        address _USDe
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker) {
        if (_stakedUSDe == address(0)) {
            revert P2pEthenaProxy__ZeroAddressStakedUSDe();
        }
        if (_USDe == address(0)) {
            revert P2pEthenaProxy__ZeroAddressUSDe();
        }

        i_stakedUSDe = _stakedUSDe;
        i_USDe = _USDe;
    }

    /// @inheritdoc IP2pYieldProxy
    function deposit(address _asset, uint256 _amount) external override onlyFactory {
        if (_asset != i_USDe) {
            revert P2pEthenaProxy__InvalidDepositAsset(_asset);
        }

        _deposit(
            i_stakedUSDe,
            abi.encodeCall(
                IERC4626.deposit,
                (_amount, address(this))
            ),
            _asset,
            _amount
        );
    }

    /// @inheritdoc IP2pEthenaProxy
    function cooldownAssets(uint256 _assets)
        external
        onlyClient
        returns (uint256 shares)
    {
        shares = IStakedUSDe(i_stakedUSDe).cooldownAssets(_assets);
        s_assetsCoolingDown += _assets;
    }

    /// @inheritdoc IP2pEthenaProxy
    function cooldownShares(uint256 _shares)
        external
        onlyClient
        returns (uint256 assets)
    {
        assets = IStakedUSDe(i_stakedUSDe).cooldownShares(_shares);
        s_assetsCoolingDown += assets;
    }

    /// @inheritdoc IP2pEthenaProxy
    function withdrawAfterCooldown() external onlyClient {
        uint256 withdrawn = _withdraw(
            i_stakedUSDe,
            i_USDe,
            abi.encodeCall(IStakedUSDe.unstake, (address(this)))
        );

        if (withdrawn >= s_assetsCoolingDown) {
            s_assetsCoolingDown = 0;
        } else {
            s_assetsCoolingDown -= withdrawn;
        }
    }

    /// @inheritdoc IP2pEthenaProxy
    function withdrawWithoutCooldown(uint256 _assets) external onlyClient {
        _withdraw(
            i_stakedUSDe,
            i_USDe,
            abi.encodeCall(
                IERC4626.withdraw,
                (_assets, address(this), address(this))
            )
        );
    }

    /// @inheritdoc IP2pEthenaProxy
    function redeemWithoutCooldown(uint256 _shares) external onlyClient {
        _withdraw(
            i_stakedUSDe,
            i_USDe,
            abi.encodeCall(
                IERC4626.redeem,
                (_shares, address(this), address(this))
            )
        );
    }

    function _getCurrentAssetAmount(
        address _yieldProtocolAddress,
        address _asset
    )
        internal
        view
        override
        returns (uint256)
    {
        if (_yieldProtocolAddress != i_stakedUSDe || _asset != i_USDe) {
            revert P2pEthenaProxy__UnsupportedAsset(_asset);
        }

        uint256 sharesBalance = IERC4626(i_stakedUSDe).balanceOf(address(this));
        uint256 assetsFromShares = IERC4626(i_stakedUSDe).previewRedeem(sharesBalance);
        return assetsFromShares + s_assetsCoolingDown;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy)
        returns (bool)
    {
        return interfaceId == type(IP2pEthenaProxy).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

