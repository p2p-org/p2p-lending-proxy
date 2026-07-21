// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/security/ReentrancyGuardUpgradeable.sol";
import "../../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../@openzeppelin/contracts/utils/Address.sol";
import "../../structs/P2pStructs.sol";
import "../P2pYieldProxyErrors.sol";
import "../IP2pYieldProxy.sol";
import "./Depositable.sol";
import "./FeeMath.sol";
import "../storage/TotalWithdrawnStorage.sol";

abstract contract Withdrawable is
    ReentrancyGuardUpgradeable,
    Depositable,
    FeeMath,
    TotalWithdrawnStorage
{
    using SafeERC20 for IERC20;
    using Address for address;

    function _withdraw(
        address _yieldProtocolAddress,
        address _asset,
        bytes memory _yieldProtocolWithdrawalCalldata
    )
        internal
        virtual
        nonReentrant
        returns (uint256)
    {
        return _executeWithdraw(
            _yieldProtocolAddress,
            _yieldProtocolAddress,
            _yieldProtocolAddress,
            _asset,
            _yieldProtocolAddress,
            _yieldProtocolWithdrawalCalldata
        );
    }

    function _withdraw(
        address _vault,
        address _asset,
        address _callTarget,
        bytes memory _yieldProtocolWithdrawalCalldata,
        uint256 _shares
    )
        internal
        virtual
        nonReentrant
        returns (uint256)
    {
        if (_shares > 0) {
            IERC20(_vault).safeIncreaseAllowance(_callTarget, _shares);
        }
        return _executeWithdraw(
            _vault,
            _callTarget,
            _vault,
            _asset,
            _callTarget,
            _yieldProtocolWithdrawalCalldata
        );
    }

    function _executeWithdraw(
        address _accrualTarget,
        address _eventYieldProtocolAddress,
        address _eventVaultAddress,
        address _asset,
        address _callTarget,
        bytes memory _yieldProtocolWithdrawalCalldata
    )
        private
        returns (uint256)
    {
        int256 accruedRewardsBefore = calculateAccruedRewards(_accrualTarget, _asset);
        uint256 newAssetAmount = _callAndGetDelta(_asset, _callTarget, _yieldProtocolWithdrawalCalldata);

        Withdrawn memory withdrawn = s_totalWithdrawn[_asset];
        (uint256 principalPortion, uint256 profitPortion) = _splitWithdrawalAmount(
            newAssetAmount,
            s_totalDeposited[_asset],
            withdrawn.amount,
            accruedRewardsBefore
        );

        uint256 totalWithdrawnAfter = _updateWithdrawnState(_asset, withdrawn, principalPortion);
        (uint256 p2pAmount, uint256 clientAmount) = _distributeWithFeeBase(_asset, newAssetAmount, profitPortion);

        emit IP2pYieldProxy.P2pYieldProxy__Withdrawn(
            _eventYieldProtocolAddress,
            _eventVaultAddress,
            _asset,
            newAssetAmount,
            totalWithdrawnAfter,
            int256(profitPortion),
            p2pAmount,
            clientAmount
        );

        return newAssetAmount;
    }

    function _getUserPrincipal(address _asset) internal view returns (uint256) {
        uint256 totalDeposited = s_totalDeposited[_asset];
        uint256 totalWithdrawn = s_totalWithdrawn[_asset].amount;
        if (totalDeposited > totalWithdrawn) {
            return totalDeposited - totalWithdrawn;
        }
        return 0;
    }

    function calculateAccruedRewards(address _yieldProtocolAddress, address _asset)
        public
        view
        virtual
        returns (int256);

    function _splitWithdrawalAmount(
        uint256 _newAssetAmount,
        uint256 _totalDeposited,
        uint256 _withdrawnAmount,
        int256 _accruedRewardsBefore
    )
        private
        view
        returns (uint256 principalPortion, uint256 profitPortion)
    {
        uint256 remainingPrincipal = _totalDeposited > _withdrawnAmount ? _totalDeposited - _withdrawnAmount : 0;
        uint256 profitFromAccrued = _min(_newAssetAmount, _positivePart(_accruedRewardsBefore));

        bool isClient = msg.sender == s_client;
        bool isClosingWithdrawal = isClient && _withdrawnAmount + _newAssetAmount >= _totalDeposited;
        if (isClosingWithdrawal) {
            principalPortion = _min(_newAssetAmount, remainingPrincipal);
            profitPortion = _newAssetAmount - principalPortion;
            return (principalPortion, profitPortion);
        }

        uint256 remainingAfterAccrued = _newAssetAmount - profitFromAccrued;
        principalPortion = _min(remainingAfterAccrued, remainingPrincipal);
        profitPortion = profitFromAccrued + (remainingAfterAccrued - principalPortion);
    }

    function _updateWithdrawnState(
        address _asset,
        Withdrawn memory _withdrawn,
        uint256 _principalPortion
    )
        private
        returns (uint256 totalWithdrawnAfter)
    {
        totalWithdrawnAfter = uint256(_withdrawn.amount) + _principalPortion;
        _withdrawn.amount = uint208(totalWithdrawnAfter);
        _withdrawn.lastFeeCollectionTime = uint48(block.timestamp);
        s_totalWithdrawn[_asset] = _withdrawn;
    }

    function _positivePart(int256 _value) private pure returns (uint256) {
        return _value > 0 ? uint256(_value) : 0;
    }

    function _min(uint256 _a, uint256 _b) private pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function _requireWithdrawnWithinAccrued(
        uint256 _withdrawn,
        int256 _accruedBefore,
        uint256 _tolerance
    ) internal pure {
        uint256 maxAllowed = _positivePart(_accruedBefore) + _tolerance;
        require(_withdrawn <= maxAllowed, P2pYieldProxy__AmountExceedsAccrued(_withdrawn, maxAllowed));
    }

    function _callAndGetDelta(
        address _asset,
        address _target,
        bytes memory _callData
    ) internal returns (uint256 delta) {
        uint256 beforeBalance = IERC20(_asset).balanceOf(address(this));
        _target.functionCall(_callData);
        delta = IERC20(_asset).balanceOf(address(this)) - beforeBalance;
    }

    function _distributeWithFeeBase(
        address _asset,
        uint256 _totalAmount,
        uint256 _feeBaseAmount
    ) internal virtual returns (uint256 p2pAmount, uint256 clientAmount) {
        p2pAmount = calculateP2pFeeAmount(_feeBaseAmount);
        clientAmount = _totalAmount - p2pAmount;

        if (p2pAmount > 0) {
            IERC20(_asset).safeTransfer(_p2pTreasuryAddress(), p2pAmount);
        }

        if (clientAmount > 0) {
            IERC20(_asset).safeTransfer(s_client, clientAmount);
        }
    }

    function _p2pTreasuryAddress() internal view virtual returns (address);
}
