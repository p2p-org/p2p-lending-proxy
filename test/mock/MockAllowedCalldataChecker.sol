// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../src/common/IAllowedCalldataChecker.sol";

/// @title MockAllowedCalldataChecker
/// @notice Test-only checker that allows ALL calldata (never reverts).
contract MockAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {
    function initialize() public initializer {}

    function checkCalldata(
        address,
        bytes4,
        bytes calldata
    ) external pure {
        // allow everything
    }

    function checkCalldataForClaimAdditionalRewardTokens(
        address,
        bytes4,
        bytes calldata
    ) external pure {
        // allow everything
    }
}
