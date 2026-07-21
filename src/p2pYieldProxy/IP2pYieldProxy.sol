// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./interfaces/IProxyInitialize.sol";
import "./interfaces/IDepositable.sol";
import "./interfaces/IAnyFunctionCallable.sol";
import "./interfaces/ICoreViews.sol";
import "./interfaces/IAccountingViews.sol";

/// @dev External interface of P2pYieldProxy declared to support ERC165 detection.
interface IP2pYieldProxy is
    IERC165,
    IProxyInitialize,
    IDepositable,
    IAnyFunctionCallable,
    ICoreViews,
    IAccountingViews
{

    /// @notice Emitted when the P2pYieldProxy is initialized
    event P2pYieldProxy__Initialized();

    /// @notice Emitted when a deposit is made
    event P2pYieldProxy__Deposited(
        address indexed _yieldProtocolAddress,
        address indexed _asset,
        uint256 _amount,
        uint256 _totalDepositedAfter
    );

    /// @notice Emitted when a withdrawal is made
    event P2pYieldProxy__Withdrawn(
        address indexed _yieldProtocolAddress,
        address indexed _vault,
        address indexed _asset,
        uint256 _assets,
        uint256 _totalWithdrawnAfter,
        int256 _accruedRewards,
        uint256 _p2pAmount,
        uint256 _clientAmount
    );

    /// @notice Emitted when an arbitrary allowed function is called
    event P2pYieldProxy__CalledAsAnyFunction(
        address indexed _yieldProtocolAddress
    );

    /// @notice Emitted when additional reward tokens are claimed and distributed
    event P2pYieldProxy__AdditionalRewardTokensClaimed(
        address indexed _target,
        address indexed _token,
        uint256 _claimedAmount,
        uint256 _p2pAmount,
        uint256 _clientAmount
    );

    // Functions are inherited from the composed interfaces.
}
