// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../src/@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../src/common/IAllowedCalldataChecker.sol";

/// @title MockAllowedCalldataChecker
/// @author P2P Validator <info@p2p.org>
/// @notice Mock. Do NOT deploy!!
contract MockAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {

    function initialize() public initializer {
        // do nothing in this implementation
    }

    /// @inheritdoc IAllowedCalldataChecker
    function checkCalldata(
        address,
        bytes4,
        bytes calldata
    ) public pure {
        // don't revert
    }
}
