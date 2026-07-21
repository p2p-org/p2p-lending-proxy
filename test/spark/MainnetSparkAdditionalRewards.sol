// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/aave/@aave/IAaveV3Pool.sol";
import "../../src/adapters/aave/@aave/IRewardsController.sol";
import "../../src/adapters/spark/p2pSparkProxy/P2pSparkProxy.sol";
import "../../src/adapters/spark/SparkRewardsAllowedCalldataChecker.sol";
import "../../src/adapters/spark/@spark/ISparkRewards.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetSparkAdditionalRewards
/// @notice End-to-end mainnet fork tests for all 4 Spark additional reward types:
///   1. SparkLend Incentives via RewardsController.claimAllRewardsToSelf (wstETH)
///   2. SparkRewards merkle claims (SPK token)
///   3. Ignition Rewards merkle claims (same SparkRewards interface)
///   4. PFL3 Rewards merkle claims (same SparkRewards interface)
contract MainnetSparkAdditionalRewards is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address constant SPARK_DATA_PROVIDER = 0xFc21d6d146E6086B8359705C8b28512a983db0cb;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Spark reward infrastructure on mainnet
    address constant SPARK_INCENTIVES_CONTROLLER = 0x4370D3b6C9588E02ce9D22e684387859c7Ff5b34;
    address constant SPARK_REWARDS = 0xbaf21A27622Db71041Bd336a573DDEdC8eB65122;
    address constant IGNITION_REWARDS = 0xCBA0C0a2a0B6Bb11233ec4EA85C5bFfea33e724d;
    address constant PFL3_REWARDS = 0x7ac96180C4d6b2A328D3a19ac059D0E7Fc3C6d41;

    // SPK token
    address constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;

    // wstETH — reward token from SparkLend Incentives
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000; // 10 USDC

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    ProxyAdmin private operatorCheckerAdmin;
    TransparentUpgradeableProxy private operatorCheckerProxy;
    ProxyAdmin private clientToP2pCheckerAdmin;
    TransparentUpgradeableProxy private clientToP2pCheckerProxy;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        // Block 22,800,000: SparkRewards, Ignition, PFL3, and Incentives Controller all deployed
        vm.createSelectFork(mainnetRpc, 22_800_000);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        operatorCheckerAdmin = new ProxyAdmin();
        operatorCheckerProxy = new TransparentUpgradeableProxy(
            address(checkerImpl), address(operatorCheckerAdmin), initData
        );

        clientToP2pCheckerAdmin = new ProxyAdmin();
        clientToP2pCheckerProxy = new TransparentUpgradeableProxy(
            address(checkerImpl), address(clientToP2pCheckerAdmin), initData
        );

        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pSparkProxy(
                address(factory),
                P2P_TREASURY,
                address(operatorCheckerProxy),
                address(clientToP2pCheckerProxy),
                SPARK_POOL,
                SPARK_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);

        // Create the proxy via deposit
        deal(USDC, client, 100e6);
        _doDeposit(USDC, DEPOSIT_AMOUNT);
    }

    // ==================== E2E: SparkLend Incentives (wstETH) ====================

    /// @notice Claim SparkLend incentives via real RewardsController on mainnet
    function test_spark_claimIncentives_e2e() external {
        _upgradeOperatorChecker();

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));

        // May not have active emissions at this block, but the call must succeed
        address[] memory tokens = new address[](0);
        vm.prank(client);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_INCENTIVES_CONTROLLER,
            claimCalldata,
            tokens
        );
    }

    // ==================== E2E: SparkRewards Merkle Claim (SPK) ====================

    /// @notice Claim SPK rewards from SparkRewards merkle contract with actual token flow + fee split
    function test_spark_claimSparkRewards_e2e() external {
        _upgradeOperatorChecker();

        uint256 claimAmount = 1000e18; // 1000 SPK
        uint256 epoch = 1;

        _doMerkleClaim(SPARK_REWARDS, SPK, claimAmount, epoch);
    }

    // ==================== E2E: Ignition Rewards Merkle Claim ====================

    /// @notice Claim from Ignition Rewards (same SparkRewards interface)
    function test_spark_claimIgnitionRewards_e2e() external {
        _upgradeOperatorChecker();

        uint256 claimAmount = 500e18;
        uint256 epoch = 1;

        _doMerkleClaim(IGNITION_REWARDS, SPK, claimAmount, epoch);
    }

    // ==================== E2E: PFL3 Rewards Merkle Claim ====================

    /// @notice Claim from PFL3 Rewards (same SparkRewards interface)
    function test_spark_claimPfl3Rewards_e2e() external {
        _upgradeOperatorChecker();

        uint256 claimAmount = 250e18;
        uint256 epoch = 1;

        _doMerkleClaim(PFL3_REWARDS, SPK, claimAmount, epoch);
    }

    // ==================== E2E: Operator Claims SparkRewards ====================

    /// @notice Operator claims SPK rewards after upgrading client-to-p2p checker
    function test_spark_claimSparkRewards_byOperator() external {
        _upgradeOperatorChecker();
        _upgradeClientToP2pChecker();

        uint256 claimAmount = 1000e18;
        uint256 epoch = 1;

        // Build merkle tree
        bytes32 leaf = _sparkRewardsLeaf(epoch, proxyAddress, SPK, claimAmount);
        bytes32 sibling = _sparkRewardsLeaf(epoch, address(0xdead), SPK, 1);
        bytes32 root = _merkleRoot(leaf, sibling);

        // Plant root and fund wallet
        _plantMerkleRoot(SPARK_REWARDS, root);
        address sparkWallet = ISparkRewards(SPARK_REWARDS).wallet();
        deal(SPK, sparkWallet, claimAmount);
        vm.prank(sparkWallet);
        IERC20(SPK).approve(SPARK_REWARDS, claimAmount);

        // Build claim calldata
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        bytes memory claimCalldata = abi.encodeCall(
            ISparkRewards.claim,
            (epoch, proxyAddress, SPK, claimAmount, root, proof)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = SPK;

        uint256 treasuryBefore = IERC20(SPK).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(SPK).balanceOf(client);

        vm.prank(p2pOperator);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_REWARDS,
            claimCalldata,
            rewardTokens
        );

        uint256 treasuryGain = IERC20(SPK).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(SPK).balanceOf(client) - clientBefore;

        uint256 expectedP2p = claimAmount * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = claimAmount - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
    }

    // ==================== E2E: Full Flow — All 4 Reward Types ====================

    /// @notice Claim all 4 reward types in sequence
    function test_spark_fullFlow_claimAll4() external {
        _upgradeOperatorChecker();

        // 1. SparkLend Incentives
        {
            address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
            address[] memory assets = new address[](1);
            assets[0] = spToken;
            bytes memory calldata1 =
                abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
            address[] memory tokens = new address[](0);
            vm.prank(client);
            P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
                SPARK_INCENTIVES_CONTROLLER, calldata1, tokens
            );
        }

        // 2. SparkRewards
        _doMerkleClaim(SPARK_REWARDS, SPK, 100e18, 1);

        // 3. Ignition Rewards
        _doMerkleClaim(IGNITION_REWARDS, SPK, 50e18, 1);

        // 4. PFL3 Rewards
        _doMerkleClaim(PFL3_REWARDS, SPK, 25e18, 1);
    }

    // ==================== Negative Tests ====================

    /// @notice Before upgrade: claimAdditionalRewardTokens reverts (default deny-all checker)
    function test_spark_claimAdditionalRewards_revertsByDefault() external {
        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_INCENTIVES_CONTROLLER, claimCalldata, tokens
        );
    }

    /// @notice After upgrade, unknown target still reverts
    function test_spark_claimAdditionalRewards_unknownTarget_stillReverts() external {
        _upgradeOperatorChecker();

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
        address[] memory tokens = new address[](0);
        address unknownTarget = makeAddr("unknownTarget");

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            unknownTarget, claimCalldata, tokens
        );
    }

    /// @notice After upgrade, known target but wrong selector still reverts
    function test_spark_claimAdditionalRewards_wrongSelector_stillReverts() external {
        _upgradeOperatorChecker();

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        // Use claimRewards (not whitelisted for incentives controller)
        bytes memory badCalldata = abi.encodeCall(
            IRewardsController.claimRewards,
            (assets, 0, address(this), address(0))
        );
        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_INCENTIVES_CONTROLLER, badCalldata, tokens
        );
    }

    /// @notice Nobody (not client or operator) cannot call claimAdditionalRewardTokens
    function test_spark_claimAdditionalRewards_revertForNobody() external {
        _upgradeOperatorChecker();

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        bytes memory claimCalldata =
            abi.encodeCall(IRewardsController.claimAllRewardsToSelf, (assets));
        address[] memory tokens = new address[](0);

        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__CallerNeitherClientNorP2pOperator.selector, nobody));
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_INCENTIVES_CONTROLLER, claimCalldata, tokens
        );
    }

    // ==================== Helpers ====================

    function _doMerkleClaim(
        address _rewardsContract,
        address _token,
        uint256 _claimAmount,
        uint256 _epoch
    ) private {
        // Build merkle tree
        bytes32 leaf = _sparkRewardsLeaf(_epoch, proxyAddress, _token, _claimAmount);
        bytes32 sibling = _sparkRewardsLeaf(_epoch, address(0xdead), _token, 1);
        bytes32 root = _merkleRoot(leaf, sibling);

        // Plant root and fund the wallet
        _plantMerkleRoot(_rewardsContract, root);
        address rewardsWallet = ISparkRewards(_rewardsContract).wallet();
        deal(_token, rewardsWallet, _claimAmount);
        vm.prank(rewardsWallet);
        IERC20(_token).approve(_rewardsContract, _claimAmount);

        // Build claim calldata
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        bytes memory claimCalldata = abi.encodeCall(
            ISparkRewards.claim,
            (_epoch, proxyAddress, _token, _claimAmount, root, proof)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = _token;

        uint256 treasuryBefore = IERC20(_token).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(_token).balanceOf(client);

        vm.prank(client);
        P2pSparkProxy(proxyAddress).claimAdditionalRewardTokens(
            _rewardsContract,
            claimCalldata,
            rewardTokens
        );

        // Verify fee distribution
        uint256 treasuryGain = IERC20(_token).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(_token).balanceOf(client) - clientBefore;

        uint256 expectedP2p = _claimAmount * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = _claimAmount - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
        assertEq(treasuryGain + clientGain, _claimAmount, "total must equal claimed");
    }

    function _sparkRewardsLeaf(uint256 _epoch, address _account, address _token, uint256 _amount)
        private
        pure
        returns (bytes32)
    {
        return keccak256(bytes.concat(
            keccak256(abi.encode(_epoch, _account, _token, _amount))
        ));
    }

    function _merkleRoot(bytes32 _a, bytes32 _b) private pure returns (bytes32) {
        if (_a < _b) {
            return keccak256(abi.encodePacked(_a, _b));
        }
        return keccak256(abi.encodePacked(_b, _a));
    }

    /// @dev SparkRewards storage layout (inherits AccessControl):
    ///   slot 0: AccessControl._roles mapping base
    ///   slot 1: wallet (address)
    ///   slot 2: merkleRoot (bytes32)
    uint256 private constant MERKLE_ROOT_SLOT = 2;

    function _plantMerkleRoot(address _rewardsContract, bytes32 _root) private {
        vm.store(_rewardsContract, bytes32(MERKLE_ROOT_SLOT), _root);
        assertEq(ISparkRewards(_rewardsContract).merkleRoot(), _root, "merkle root not set");
    }

    function _upgradeOperatorChecker() private {
        SparkRewardsAllowedCalldataChecker sparkChecker =
            new SparkRewardsAllowedCalldataChecker(
                SPARK_INCENTIVES_CONTROLLER,
                SPARK_REWARDS,
                IGNITION_REWARDS,
                PFL3_REWARDS
            );

        vm.prank(p2pOperator);
        operatorCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(operatorCheckerProxy)),
            address(sparkChecker)
        );
    }

    function _upgradeClientToP2pChecker() private {
        SparkRewardsAllowedCalldataChecker sparkChecker =
            new SparkRewardsAllowedCalldataChecker(
                SPARK_INCENTIVES_CONTROLLER,
                SPARK_REWARDS,
                IGNITION_REWARDS,
                PFL3_REWARDS
            );

        vm.prank(p2pOperator);
        clientToP2pCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)),
            address(sparkChecker)
        );
    }

    function _doDeposit(address _asset, uint256 _amount) private {
        bytes memory sig = _getP2pSignerSignature();
        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, _asset, _amount, CLIENT_BPS, block.timestamp + 1 hours, sig);
        vm.stopPrank();
    }

    function _getP2pSignerSignature() private view returns (bytes memory) {
        bytes32 hashForSigner =
            factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, block.timestamp + 1 hours);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}
