// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../../@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "../../../p2pYieldProxy/IP2pYieldProxy.sol";

interface IP2pSuperformProxy is IP2pYieldProxy, IERC1155Receiver {
    event P2pSuperformProxy__Claimed(
        address indexed _token, uint256 _totalAmount, uint256 _p2pAmount, uint256 _clientAmount
    );

    /// @notice Withdraw assets from Superform protocol
    /// @param _superformCalldata calldata for withdraw function of Superform protocol
    function withdraw(bytes calldata _superformCalldata) external;

    /// @notice Withdraw only accrued rewards from Superform protocol
    /// @param _superformCalldata calldata for withdraw function of Superform protocol
    function withdrawAccruedRewards(bytes calldata _superformCalldata) external;

    /// @notice Claims queued rewards from the Superform rewards distributor
    /// @param _periodIds Reward period identifiers being claimed
    /// @param _rewardTokens Nested array containing reward token addresses for each period
    /// @param _amountsClaimed Nested array containing amounts being claimed for each reward token
    /// @param _proofs Nested array with Merkle proofs proving eligibility for each reward entry
    function batchClaim(
        uint256[] calldata _periodIds,
        address[][] calldata _rewardTokens,
        uint256[][] calldata _amountsClaimed,
        bytes32[][] calldata _proofs
    ) external;
}
