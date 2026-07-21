// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../@openzeppelin/contracts/utils/Address.sol";
import "../P2pYieldProxyErrors.sol";
import "../IP2pYieldProxy.sol";
import "./FactoryCallable.sol";
import "../storage/TotalDepositedStorage.sol";
import "../storage/ClientStorage.sol";

abstract contract Depositable is
    FactoryCallable,
    TotalDepositedStorage,
    ClientStorage
{
    using SafeERC20 for IERC20;
    using Address for address;

    function _deposit(
        address _yieldProtocolAddress,
        bytes memory _yieldProtocolDepositCalldata,
        address _asset,
        uint256 _amount
    )
        internal
        onlyFactory
    {
        _deposit(
            _yieldProtocolAddress,
            _yieldProtocolAddress,
            _yieldProtocolDepositCalldata,
            _asset,
            _amount,
            false
        );
    }

    function _deposit(
        address _vault,
        address _callTarget,
        bytes memory _yieldProtocolDepositCalldata,
        address _asset,
        uint256 _amount,
        bool _transferBeforeCall
    ) internal onlyFactory {
        require(_asset != address(0), P2pYieldProxy__ZeroAddressAsset());
        require(_amount > 0, P2pYieldProxy__ZeroAssetAmount());

        address client = s_client;
        uint256 assetAmountBefore = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).safeTransferFrom(client, address(this), _amount);
        uint256 actualAmount = IERC20(_asset).balanceOf(address(this)) - assetAmountBefore;

        require(
            actualAmount == _amount,
            P2pYieldProxy__DifferentActuallyDepositedAmount(_amount, actualAmount)
        );

        uint256 totalDepositedAfter = s_totalDeposited[_asset] + actualAmount;
        s_totalDeposited[_asset] = totalDepositedAfter;
        emit IP2pYieldProxy.P2pYieldProxy__Deposited(_vault, _asset, actualAmount, totalDepositedAfter);

        if (_transferBeforeCall) {
            IERC20(_asset).safeTransfer(_callTarget, actualAmount);
        } else {
            IERC20(_asset).safeIncreaseAllowance(_callTarget, actualAmount);
        }

        _callTarget.functionCall(_yieldProtocolDepositCalldata);
    }
}
