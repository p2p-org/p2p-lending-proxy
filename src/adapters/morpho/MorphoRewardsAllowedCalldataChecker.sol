// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts-upgradable/proxy/utils/Initializable.sol";
import "../../common/AllowedCalldataChecker.sol";
import "./@morpho/IDistributor.sol";
import "../../mocks/IUniversalRewardsDistributor.sol";

/// @title MorphoRewardsAllowedCalldataChecker
/// @notice Whitelists calldata patterns for claiming Morpho additional rewards
///   via the generic `claimAdditionalRewardTokens` flow on P2pErc4626Proxy:
///   - Morpho URD (Universal Rewards Distributor): claim(account, reward, claimable, proof)
///   - Merkl Distributor: claim(users[], tokens[], amounts[], proofs[][])
///
///   Security: Both claim types are Merkle-proof-gated, so token redirection is not possible.
///   No target address restriction is needed — any URD or Merkl distributor is safe to call.
contract MorphoRewardsAllowedCalldataChecker is IAllowedCalldataChecker, Initializable {
    bytes4 private constant URD_CLAIM_SELECTOR =
        IUniversalRewardsDistributorBase.claim.selector;
    bytes4 private constant MERKL_CLAIM_SELECTOR =
        IDistributor.claim.selector;

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
        address,
        bytes4 _selector,
        bytes calldata
    ) external pure {
        // Morpho URD: claim(address account, address reward, uint256 claimable, bytes32[] proof)
        if (_selector == URD_CLAIM_SELECTOR) {
            return;
        }

        // Merkl Distributor: claim(address[] users, address[] tokens, uint256[] amounts, bytes32[][] proofs)
        if (_selector == MERKL_CLAIM_SELECTOR) {
            return;
        }

        revert AllowedCalldataChecker__NoAllowedCalldata();
    }
}
