// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../common/AllowedCalldataChecker.sol";
import "./@aave/IRewardsController.sol";
import "../morpho/@morpho/IDistributor.sol";

/// @title AaveRewardsAllowedCalldataChecker
/// @notice Whitelists calldata patterns for claiming additional Aave rewards:
///   - Aave Governance rewards via RewardsController.claimAllRewardsToSelf
///   - Safety/Umbrella staking incentives via Umbrella RewardsController.claimAllRewards
///   - Merit rewards via Merkl Distributor.claim
contract AaveRewardsAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {
    address public immutable i_aaveRewardsController;
    address public immutable i_umbrellaRewardsController;
    address public immutable i_merklDistributor;

    bytes4 private constant CLAIM_ALL_REWARDS_TO_SELF_SELECTOR =
        IRewardsController.claimAllRewardsToSelf.selector;
    bytes4 private constant CLAIM_ALL_REWARDS_SELECTOR =
        IRewardsController.claimAllRewards.selector;
    bytes4 private constant MERKL_CLAIM_SELECTOR =
        IDistributor.claim.selector;

    constructor(
        address _aaveRewardsController,
        address _umbrellaRewardsController,
        address _merklDistributor
    ) {
        i_aaveRewardsController = _aaveRewardsController;
        i_umbrellaRewardsController = _umbrellaRewardsController;
        i_merklDistributor = _merklDistributor;
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
        // Aave V3 RewardsController: claimAllRewardsToSelf (safest — rewards always go to msg.sender)
        if (_target == i_aaveRewardsController) {
            if (_selector == CLAIM_ALL_REWARDS_TO_SELF_SELECTOR) {
                return;
            }
        }

        // Umbrella RewardsController: claimAllRewards (no claimAllRewardsToSelf in Umbrella interface)
        if (_target == i_umbrellaRewardsController) {
            if (_selector == CLAIM_ALL_REWARDS_SELECTOR) {
                return;
            }
        }

        // Merkl Distributor: claim
        if (_target == i_merklDistributor) {
            if (_selector == MERKL_CLAIM_SELECTOR) {
                return;
            }
        }

        revert AllowedCalldataChecker__NoAllowedCalldata();
    }
}
