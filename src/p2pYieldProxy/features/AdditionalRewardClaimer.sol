// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/security/ReentrancyGuardUpgradeable.sol";
import "../../@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../@openzeppelin/contracts/utils/Address.sol";
import "../../common/IAllowedCalldataChecker.sol";
import "../../access/P2pOperatorCallable.sol";
import "../storage/ClientStorage.sol";
import "../IP2pYieldProxy.sol";
import "../P2pYieldProxyErrors.sol";

/// @title AdditionalRewardClaimer
/// @notice Provides generalized reward claiming with fee distribution.
/// Supports two execution paths:
///   - client calls → calldata validated against p2pOperator's checker (i_allowedCalldataChecker)
///   - p2pOperator calls → calldata validated against client's checker (i_allowedCalldataByClientToP2pChecker)
abstract contract AdditionalRewardClaimer is
    ReentrancyGuardUpgradeable,
    P2pOperatorCallable,
    ClientStorage
{
    using Address for address;

    /// @notice Returns the p2pOperator-controlled calldata checker (existing)
    function _allowedCalldataChecker() internal view virtual returns (IAllowedCalldataChecker);

    /// @notice Returns the client-controlled calldata checker (new)
    function _allowedCalldataByClientToP2pChecker() internal view virtual returns (IAllowedCalldataChecker);

    /// @notice Distributes tokens between p2pTreasury and client, applying fee on the given base amount
    function _distributeWithFeeBase(
        address _asset,
        uint256 _totalAmount,
        uint256 _feeBaseAmount
    ) internal virtual returns (uint256 p2pAmount, uint256 clientAmount);

    /// @notice Calls an arbitrary function on a target contract, validated against the client's checker.
    /// @param _target The address to call
    /// @param _callData The calldata to pass
    function callAnyFunctionByP2pOperator(
        address _target,
        bytes calldata _callData
    )
        public
        virtual
        onlyP2pOperator
        nonReentrant
    {
        require(_callData.length >= 4, P2pYieldProxy__DataTooShort());

        bytes4 selector = bytes4(_callData[:4]);
        _allowedCalldataByClientToP2pChecker().checkCalldata(
            _target,
            selector,
            _callData[4:]
        );

        emit IP2pYieldProxy.P2pYieldProxy__CalledAsAnyFunction(_target);
        _target.functionCall(_callData);
    }

    /// @notice Claims additional reward tokens, splitting them between p2pTreasury and client.
    /// Either client or p2pOperator may call. The caller's action is validated against the other
    /// party's calldata checker (client → p2pOperator's checker, p2pOperator → client's checker).
    /// @param _target The distributor/rewards contract to call
    /// @param _callData The calldata for the claim call
    /// @param _tokens The token addresses expected to be received
    function claimAdditionalRewardTokens(
        address _target,
        bytes calldata _callData,
        address[] calldata _tokens
    )
        external
        nonReentrant
    {
        require(
            msg.sender == s_client || _isP2pOperator(msg.sender),
            P2pYieldProxy__CallerNeitherClientNorP2pOperator(msg.sender)
        );
        require(_callData.length >= 4, P2pYieldProxy__DataTooShort());

        bytes4 selector = bytes4(_callData[:4]);
        if (msg.sender == s_client) {
            _allowedCalldataChecker().checkCalldataForClaimAdditionalRewardTokens(_target, selector, _callData[4:]);
        } else {
            _allowedCalldataByClientToP2pChecker().checkCalldataForClaimAdditionalRewardTokens(_target, selector, _callData[4:]);
        }

        uint256 tokenCount = _tokens.length;
        uint256[] memory balancesBefore = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; ++i) {
            balancesBefore[i] = IERC20(_tokens[i]).balanceOf(address(this));
        }

        _target.functionCall(_callData);

        for (uint256 i; i < tokenCount; ++i) {
            address tokenAddress = _tokens[i];
            uint256 delta = IERC20(tokenAddress).balanceOf(address(this)) - balancesBefore[i];
            if (delta > 0) {
                (uint256 p2pAmount, uint256 clientAmount) = _distributeWithFeeBase(
                    tokenAddress,
                    delta,
                    delta
                );

                emit IP2pYieldProxy.P2pYieldProxy__AdditionalRewardTokensClaimed(
                    _target,
                    tokenAddress,
                    delta,
                    p2pAmount,
                    clientAmount
                );
            }
        }
    }
}
