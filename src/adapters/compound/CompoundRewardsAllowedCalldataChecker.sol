// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../common/AllowedCalldataChecker.sol";
import "./@compound/ICometRewards.sol";

/// @title CompoundRewardsAllowedCalldataChecker
/// @notice Whitelists calldata patterns for claiming Compound V3 COMP rewards:
///   - CometRewards.claim(address comet, address src, bool shouldAccrue)
contract CompoundRewardsAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {
    address public immutable i_cometRewards;

    bytes4 private constant CLAIM_SELECTOR = ICometRewards.claim.selector;

    constructor(address _cometRewards) {
        i_cometRewards = _cometRewards;
    }

    function initialize() public initializer {}

    /// @inheritdoc IAllowedCalldataChecker
    function checkCalldata(
        address,
        bytes4,
        bytes calldata
    ) external pure {
        revert AllowedCalldataChecker__NoAllowedCalldata();
    }

    /// @inheritdoc IAllowedCalldataChecker
    function checkCalldataForClaimAdditionalRewardTokens(
        address _target,
        bytes4 _selector,
        bytes calldata
    ) external view {
        if (_target == i_cometRewards) {
            if (_selector == CLAIM_SELECTOR) {
                return;
            }
        }

        revert AllowedCalldataChecker__NoAllowedCalldata();
    }
}
