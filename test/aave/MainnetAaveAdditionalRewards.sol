// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/aave/p2pAaveProxy/P2pAaveProxy.sol";
import "../../src/adapters/aave/AaveRewardsAllowedCalldataChecker.sol";
import "../../src/adapters/aave/@aave/IRewardsController.sol";
import "../../src/adapters/morpho/@morpho/IDistributor.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetAaveAdditionalRewards
/// @notice End-to-end mainnet fork tests for all 3 Aave additional reward types:
///   1. Aave Governance rewards (RewardsController.claimAllRewardsToSelf)
///   2. Umbrella Safety/staking incentives (Umbrella RewardsController.claimAllRewards)
///   3. Merit rewards (Merkl Distributor.claim)
contract MainnetAaveAdditionalRewards is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Aave rewards infrastructure on mainnet
    address constant AAVE_REWARDS_CONTROLLER = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address constant UMBRELLA_REWARDS_CONTROLLER = 0x4655Ce3D625a63d30bA704087E52B4C31E38188B;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    // Umbrella StakeToken for USDC (stkwaEthUSDC.v1) — registered asset in Umbrella RewardsController
    address constant STK_WA_ETH_USDC = 0x6bf183243FdD1e306ad2C4450BC7dcf6f0bf8Aa6;

    // GHO — used as reward token for Merkl test
    address constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

    // Merkl Distributor storage: slot 101 = tree.merkleRoot (pending), slot 103 = lastTree.merkleRoot (active).
    // getMerkleRoot() returns lastTree when dispute period is active (block.timestamp < endOfDisputePeriod).
    uint256 constant MERKL_LAST_TREE_ROOT_SLOT = 103;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000; // 10 USDC

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    // Checker infrastructure
    ProxyAdmin private operatorCheckerAdmin;
    TransparentUpgradeableProxy private operatorCheckerProxy;
    ProxyAdmin private clientToP2pCheckerAdmin;
    TransparentUpgradeableProxy private clientToP2pCheckerProxy;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        // Block 22,800,000: Umbrella StakeTokens registered, all 3 reward controllers deployed
        vm.createSelectFork(mainnetRpc, 22_800_000);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        // Deploy p2pOperator-controlled checker (allows client calls)
        AllowedCalldataChecker operatorImpl = new AllowedCalldataChecker();
        operatorCheckerAdmin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        operatorCheckerProxy = new TransparentUpgradeableProxy(
            address(operatorImpl), address(operatorCheckerAdmin), initData
        );

        // Deploy client-controlled checker (allows p2pOperator calls)
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        clientToP2pCheckerAdmin = new ProxyAdmin();
        clientToP2pCheckerProxy = new TransparentUpgradeableProxy(
            address(clientToP2pImpl), address(clientToP2pCheckerAdmin), initData
        );

        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pAaveProxy(
                address(factory),
                P2P_TREASURY,
                address(operatorCheckerProxy),
                address(clientToP2pCheckerProxy),
                AAVE_POOL,
                AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);

        // Do a deposit to create the proxy
        deal(USDC, client, 100e6);
        _doDeposit(USDC, DEPOSIT_AMOUNT);
    }

    // ==================== E2E: Aave Governance Rewards ====================

    /// @notice Deposit into Aave, upgrade checker, claim Aave Governance rewards via real RewardsController
    function test_aave_claimGovernanceRewards_e2e() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));

        // No active Aave Governance emissions on mainnet at this block,
        // but the call must succeed (returns 0 rewards gracefully)
        address[] memory tokens = new address[](0);
        vm.prank(client);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            AAVE_REWARDS_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    // ==================== E2E: Umbrella Safety/Staking Rewards ====================

    /// @notice Deposit into Aave, upgrade checker, claim Umbrella rewards via real Umbrella RewardsController.
    /// Uses claimAllRewards(address[],address) — the correct Umbrella interface (not claimAllRewardsToSelf).
    function test_aave_claimUmbrellaRewards_e2e() external {
        _upgradeChecker();

        // Umbrella uses StakeToken addresses, not aTokens
        address[] memory umbrellaAssets = new address[](1);
        umbrellaAssets[0] = STK_WA_ETH_USDC;

        // claimAllRewards(address[] assets, address receiver) — Umbrella interface
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewards, (umbrellaAssets, proxyAddress));

        // No active Umbrella rewards for this proxy, but the call must succeed
        address[] memory tokens = new address[](0);
        vm.prank(client);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            UMBRELLA_REWARDS_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    // ==================== E2E: Merit / Merkl Rewards ====================

    /// @notice Deposit into Aave, upgrade checker, claim Merkl rewards with actual GHO token flow + fee split.
    /// Uses vm.store to plant a Merkle root (like deal() plants token balances) and the real
    /// Merkl Distributor contract validates the proof, transfers tokens, and tracks claimed amounts.
    function test_aave_claimMerklRewards_e2e() external {
        _upgradeChecker();

        uint256 claimAmount = 1000e18; // 1000 GHO

        // --- Build Merkle tree ---
        bytes32 leaf0 = keccak256(abi.encode(proxyAddress, GHO, claimAmount));
        bytes32 leaf1 = keccak256(abi.encode(address(0xdead), GHO, uint256(1)));

        // Standard sorted-pair Merkle root
        bytes32 root;
        if (leaf0 < leaf1) {
            root = keccak256(abi.encode(leaf0, leaf1));
        } else {
            root = keccak256(abi.encode(leaf1, leaf0));
        }

        // --- Plant Merkle root in the real Merkl Distributor (slot 101) ---
        vm.store(MERKL_DISTRIBUTOR, bytes32(uint256(MERKL_LAST_TREE_ROOT_SLOT)), root);

        // --- Fund the Merkl Distributor with GHO ---
        deal(GHO, MERKL_DISTRIBUTOR, claimAmount);

        // --- Construct IDistributor.claim calldata ---
        address[] memory users = new address[](1);
        users[0] = proxyAddress;
        address[] memory claimTokens = new address[](1);
        claimTokens[0] = GHO;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = leaf1; // sibling in the 2-leaf tree

        bytes memory claimCalldata = abi.encodeCall(
            IDistributor.claim,
            (users, claimTokens, amounts, proofs)
        );

        // --- Claim via claimAdditionalRewardTokens ---
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = GHO;

        uint256 treasuryBefore = IERC20(GHO).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(GHO).balanceOf(client);

        vm.prank(client);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            MERKL_DISTRIBUTOR,
            claimCalldata,
            rewardTokens
        );

        // --- Verify fee distribution ---
        uint256 treasuryGain = IERC20(GHO).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(GHO).balanceOf(client) - clientBefore;

        uint256 expectedP2p = claimAmount * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = claimAmount - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
        assertEq(treasuryGain + clientGain, claimAmount, "total must equal claimed");
    }

    // ==================== E2E: Full Flow — Deposit + Withdraw + Claim All 3 ====================

    /// @notice Full lifecycle: deposit → withdraw → claim all 3 additional reward types
    function test_aave_fullFlow_deposit_withdraw_claimAll3() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);

        // --- Withdraw some USDC (proves normal proxy operation) ---
        vm.prank(client);
        P2pAaveProxy(proxyAddress).withdraw(USDC, DEPOSIT_AMOUNT / 2);

        // --- 1. Claim Aave Governance rewards ---
        {
            address[] memory assets = new address[](1);
            assets[0] = aToken;
            bytes memory calldata1 =
                abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
            address[] memory tokens = new address[](0);

            vm.prank(client);
            P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
                AAVE_REWARDS_CONTROLLER,
                calldata1,
                tokens
            );
        }

        // --- 2. Claim Umbrella rewards ---
        {
            address[] memory umbrellaAssets = new address[](1);
            umbrellaAssets[0] = STK_WA_ETH_USDC;
            bytes memory calldata2 =
                abi.encodeCall(IRewardsController.claimAllRewards, (umbrellaAssets, proxyAddress));
            address[] memory tokens = new address[](0);

            vm.prank(client);
            P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
                UMBRELLA_REWARDS_CONTROLLER,
                calldata2,
                tokens
            );
        }

        // --- 3. Claim Merkl rewards (actual GHO flow) ---
        {
            uint256 claimAmount = 500e18;
            bytes32 leaf0 = keccak256(abi.encode(proxyAddress, GHO, claimAmount));
            bytes32 leaf1 = keccak256(abi.encode(address(0xdead), GHO, uint256(1)));

            bytes32 root;
            if (leaf0 < leaf1) {
                root = keccak256(abi.encode(leaf0, leaf1));
            } else {
                root = keccak256(abi.encode(leaf1, leaf0));
            }

            vm.store(MERKL_DISTRIBUTOR, bytes32(uint256(MERKL_LAST_TREE_ROOT_SLOT)), root);
            deal(GHO, MERKL_DISTRIBUTOR, claimAmount);

            address[] memory users = new address[](1);
            users[0] = proxyAddress;
            address[] memory claimTokens = new address[](1);
            claimTokens[0] = GHO;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = claimAmount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = leaf1;

            bytes memory calldata3 = abi.encodeCall(
                IDistributor.claim,
                (users, claimTokens, amounts, proofs)
            );
            address[] memory rewardTokens = new address[](1);
            rewardTokens[0] = GHO;

            uint256 clientBefore = IERC20(GHO).balanceOf(client);

            vm.prank(client);
            P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
                MERKL_DISTRIBUTOR,
                calldata3,
                rewardTokens
            );

            uint256 clientGain = IERC20(GHO).balanceOf(client) - clientBefore;
            assertGt(clientGain, 0, "client should receive GHO rewards");
        }
    }

    // ==================== Negative Tests ====================

    /// @notice Before upgrade: claimAdditionalRewardTokens reverts because checker blocks everything
    function test_aave_claimAdditionalRewards_revertsByDefault() external {
        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);

        address[] memory assets = new address[](1);
        assets[0] = aToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));

        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            AAVE_REWARDS_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    /// @notice After upgrade, calldata targeting an unknown address still reverts
    function test_aave_claimAdditionalRewards_unknownTarget_stillReverts() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));

        address[] memory tokens = new address[](0);
        address unknownTarget = makeAddr("unknownTarget");

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            unknownTarget,
            claimCalldata,
            tokens
        );
    }

    /// @notice After upgrade, known target but unknown selector still reverts
    function test_aave_claimAdditionalRewards_unknownSelector_stillReverts() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);

        // Use claimRewards (wrong selector — not whitelisted)
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        bytes memory badCalldata = abi.encodeCall(
            IRewardsController.claimRewards,
            (assets, 0, address(this), address(0))
        );

        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            AAVE_REWARDS_CONTROLLER,
            badCalldata,
            tokens
        );
    }

    /// @notice Umbrella: claimAllRewardsToSelf is NOT whitelisted for Umbrella controller
    function test_aave_umbrella_claimAllRewardsToSelf_reverts() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = aToken;

        // claimAllRewardsToSelf does not exist on Umbrella — and is not whitelisted
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));

        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            UMBRELLA_REWARDS_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    // ==================== E2E: Operator Claims Merkl Rewards ====================

    /// @notice Operator claims Merkl GHO rewards after upgrading client-to-p2p checker
    function test_aave_claimMerklRewards_byOperator() external {
        _upgradeChecker();
        _upgradeClientToP2pChecker();

        uint256 claimAmount = 1000e18;

        bytes32 leaf0 = keccak256(abi.encode(proxyAddress, GHO, claimAmount));
        bytes32 leaf1 = keccak256(abi.encode(address(0xdead), GHO, uint256(1)));

        bytes32 root;
        if (leaf0 < leaf1) {
            root = keccak256(abi.encode(leaf0, leaf1));
        } else {
            root = keccak256(abi.encode(leaf1, leaf0));
        }

        vm.store(MERKL_DISTRIBUTOR, bytes32(uint256(MERKL_LAST_TREE_ROOT_SLOT)), root);
        deal(GHO, MERKL_DISTRIBUTOR, claimAmount);

        address[] memory users = new address[](1);
        users[0] = proxyAddress;
        address[] memory claimTokens = new address[](1);
        claimTokens[0] = GHO;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = leaf1;

        bytes memory claimCalldata = abi.encodeCall(
            IDistributor.claim,
            (users, claimTokens, amounts, proofs)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = GHO;

        uint256 treasuryBefore = IERC20(GHO).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(GHO).balanceOf(client);

        vm.prank(p2pOperator);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            MERKL_DISTRIBUTOR,
            claimCalldata,
            rewardTokens
        );

        uint256 treasuryGain = IERC20(GHO).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(GHO).balanceOf(client) - clientBefore;

        uint256 expectedP2p = claimAmount * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = claimAmount - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
    }

    /// @notice Nobody (not client or operator) cannot call claimAdditionalRewardTokens
    function test_aave_claimAdditionalRewards_revertForNobody() external {
        _upgradeChecker();

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
        address[] memory tokens = new address[](0);

        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__CallerNeitherClientNorP2pOperator.selector, nobody));
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            AAVE_REWARDS_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    // ==================== Helpers ====================

    function _upgradeClientToP2pChecker() private {
        AaveRewardsAllowedCalldataChecker aaveChecker =
            new AaveRewardsAllowedCalldataChecker(
                AAVE_REWARDS_CONTROLLER,
                UMBRELLA_REWARDS_CONTROLLER,
                MERKL_DISTRIBUTOR
            );

        vm.prank(p2pOperator);
        clientToP2pCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)),
            address(aaveChecker)
        );
    }

    function _upgradeChecker() private {
        AaveRewardsAllowedCalldataChecker aaveChecker =
            new AaveRewardsAllowedCalldataChecker(
                AAVE_REWARDS_CONTROLLER,
                UMBRELLA_REWARDS_CONTROLLER,
                MERKL_DISTRIBUTOR
            );

        vm.prank(p2pOperator);
        operatorCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(operatorCheckerProxy)),
            address(aaveChecker)
        );
    }

    function _doDeposit(address _asset, uint256 _amount) private {
        bytes memory sig = _getP2pSignerSignature();
        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, _asset, _amount, CLIENT_BPS, 1_800_000_000, sig);
        vm.stopPrank();
    }

    function _getP2pSignerSignature() private view returns (bytes memory) {
        bytes32 hashForSigner =
            factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, 1_800_000_000);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}
