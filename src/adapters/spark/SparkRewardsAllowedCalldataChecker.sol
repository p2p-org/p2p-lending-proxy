// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../common/AllowedCalldataChecker.sol";
import "../aave/@aave/IRewardsController.sol";
import "./@spark/ISparkRewards.sol";

/// @title SparkRewardsAllowedCalldataChecker
/// @notice Whitelists calldata patterns for claiming all types of Spark additional rewards:
///   1. SparkLend Incentives via RewardsController.claimAllRewardsToSelf (wstETH rewards)
///   2. SparkRewards merkle claims via SparkRewards.claim (SPK token)
///   3. Ignition Rewards merkle claims via SparkRewards.claim (same interface)
///   4. PFL3 Rewards merkle claims via SparkRewards.claim (same interface)
contract SparkRewardsAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {
    address public immutable i_sparkIncentivesController;
    address public immutable i_sparkRewards;
    address public immutable i_ignitionRewards;
    address public immutable i_pfl3Rewards;

    bytes4 private constant CLAIM_ALL_REWARDS_TO_SELF_SELECTOR =
        IRewardsController.claimAllRewardsToSelf.selector;
    bytes4 private constant SPARK_REWARDS_CLAIM_SELECTOR =
        ISparkRewards.claim.selector;

    constructor(
        address _sparkIncentivesController,
        address _sparkRewards,
        address _ignitionRewards,
        address _pfl3Rewards
    ) {
        i_sparkIncentivesController = _sparkIncentivesController;
        i_sparkRewards = _sparkRewards;
        i_ignitionRewards = _ignitionRewards;
        i_pfl3Rewards = _pfl3Rewards;
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
        // SparkLend Incentives: claimAllRewardsToSelf (Aave V3-style, distributes wstETH)
        if (_target == i_sparkIncentivesController) {
            if (_selector == CLAIM_ALL_REWARDS_TO_SELF_SELECTOR) {
                return;
            }
        }

        // SparkRewards: merkle claim (SPK token distribution)
        if (_target == i_sparkRewards) {
            if (_selector == SPARK_REWARDS_CLAIM_SELECTOR) {
                return;
            }
        }

        // Ignition Rewards: merkle claim (same SparkRewards interface)
        if (_target == i_ignitionRewards) {
            if (_selector == SPARK_REWARDS_CLAIM_SELECTOR) {
                return;
            }
        }

        // PFL3 Rewards: merkle claim (same SparkRewards interface)
        if (_target == i_pfl3Rewards) {
            if (_selector == SPARK_REWARDS_CLAIM_SELECTOR) {
                return;
            }
        }

        revert AllowedCalldataChecker__NoAllowedCalldata();
    }
}
