// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/adapters/spark/SparkRewardsAllowedCalldataChecker.sol";
import "../../src/adapters/spark/@spark/ISparkRewards.sol";
import "../../src/adapters/aave/@aave/IRewardsController.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetSparkVaultsIntegration
/// @notice Ethereum mainnet fork tests for Spark USDC Vault (sUSDC) via P2pErc4626Proxy.
///   Spark USDC Vault is an ERC-4626 vault that converts USDC → USDS → sUSDS,
///   earning yield via the Spark Savings Rate (SSR).
///   SparkRewards claiming is tested via claimAdditionalRewardTokens.
contract MainnetSparkVaultsIntegration is Test {
    using SafeERC20 for IERC20;

    // ===================== Spark USDC Vault =====================
    address constant SPARK_USDC_VAULT = 0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE;

    // ===================== Underlying Tokens =====================
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // ===================== Spark Rewards Infrastructure =====================
    address constant SPARK_INCENTIVES_CONTROLLER = 0x4370D3b6C9588E02ce9D22e684387859c7Ff5b34;
    address constant SPARK_REWARDS = 0xbaf21A27622Db71041Bd336a573DDEdC8eB65122;
    address constant IGNITION_REWARDS = 0xCBA0C0a2a0B6Bb11233ec4EA85C5bFfea33e724d;
    address constant PFL3_REWARDS = 0x7ac96180C4d6b2A328D3a19ac059D0E7Fc3C6d41;

    // SPK token
    address constant SPK = 0xc20059e0317DE91738d13af027DfC4a50781b066;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceProxy;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;

    address private proxyAddress;

    ProxyAdmin private operatorCheckerAdmin;
    TransparentUpgradeableProxy private operatorCheckerProxy;
    ProxyAdmin private clientToP2pCheckerAdmin;
    TransparentUpgradeableProxy private clientToP2pCheckerProxy;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        // Block 22,800,000: Spark Vault deployed, SparkRewards active
        vm.createSelectFork(rpc, 22_800_000);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

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
            new P2pErc4626Proxy(
                address(factory), P2P_TREASURY,
                address(operatorCheckerProxy), address(clientToP2pCheckerProxy)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);

        // Verify Spark Vault is ERC-4626 with USDC as underlying
        assertEq(IERC4626(SPARK_USDC_VAULT).asset(), USDC, "Spark Vault asset should be USDC");
    }

    // ========================= Deposit / Withdraw =========================

    function test_sparkVault_deposit_withdraw() external {
        uint256 amount = 10_000e6;
        deal(USDC, client, amount);
        _doDeposit(SPARK_USDC_VAULT, amount);

        uint256 shares = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold vault shares");

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(SPARK_USDC_VAULT, shares);

        uint256 clientBal = IERC20(USDC).balanceOf(client);
        // Allow small rounding/PSM fee loss
        assertGe(clientBal, amount - 10, "client should recover funds (minus PSM fees)");
    }

    // ========================= Yield Accrual =========================

    function test_sparkVault_yieldAccrual() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(SPARK_USDC_VAULT, depositAmt);

        // sUSDS yield accrues via SSR (Spark Savings Rate) over time
        vm.warp(block.timestamp + 365 days);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(SPARK_USDC_VAULT, USDC);
        assertGt(accrued, 0, "should have accrued rewards from SSR");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(SPARK_USDC_VAULT);

        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGt(treasuryDelta + clientDelta, 0, "should have distributed rewards");
        assertGt(treasuryDelta, 0, "treasury should receive fee");
        assertGt(clientDelta, 0, "client should receive share");
    }

    // ========================= Fee Split =========================

    function test_sparkVault_feeSplit() external {
        uint256 depositAmt = 500_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(SPARK_USDC_VAULT, depositAmt);

        vm.warp(block.timestamp + 365 days);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(SPARK_USDC_VAULT, USDC);
        assertGt(accrued, 0, "should have accrued");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(SPARK_USDC_VAULT);

        uint256 treasuryGain = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(USDC).balanceOf(client) - clientBefore;
        uint256 totalDistributed = treasuryGain + clientGain;

        // CLIENT_BPS = 9_000 → client gets 90%, treasury gets 10%
        uint256 expectedP2p = totalDistributed * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = totalDistributed - expectedP2p;

        // Allow 1 wei rounding
        assertApproxEqAbs(treasuryGain, expectedP2p, 1, "p2p fee mismatch");
        assertApproxEqAbs(clientGain, expectedClient, 1, "client amount mismatch");
    }

    // ========================= Principal Protection =========================

    function test_sparkVault_principalProtection() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(SPARK_USDC_VAULT, depositAmt);

        vm.warp(block.timestamp + 365 days);

        vm.prank(p2pOperator);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(SPARK_USDC_VAULT);

        uint256 remainingShares = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(SPARK_USDC_VAULT, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        // Allow small PSM fee / rounding loss
        assertGe(clientPrincipal, depositAmt - 10, "client should recover principal");
    }

    // ========================= Access Control =========================

    function test_sparkVault_onlyClient_canWithdraw() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        uint256 shares = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);

        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(SPARK_USDC_VAULT, shares);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(SPARK_USDC_VAULT, shares);
    }

    function test_sparkVault_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, 100_000e6);
        _doDeposit(SPARK_USDC_VAULT, 100_000e6);

        vm.warp(block.timestamp + 365 days);

        vm.prank(client);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(SPARK_USDC_VAULT);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(SPARK_USDC_VAULT);
    }

    // ========================= Zero Accrued Reverts =========================

    function test_sparkVault_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pErc4626Proxy__ZeroAccruedRewards.selector);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(SPARK_USDC_VAULT);
    }

    // ========================= Multiple Deposits =========================

    function test_sparkVault_multipleDeposits() external {
        uint256 first = 50_000e6;
        uint256 second = 30_000e6;
        deal(USDC, client, first + second);

        _doDeposit(SPARK_USDC_VAULT, first);
        uint256 s1 = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);
        assertGt(s1, 0);

        _doDeposit(SPARK_USDC_VAULT, second);
        uint256 s2 = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);
        assertGt(s2, s1);

        assertEq(
            P2pErc4626Proxy(proxyAddress).getTotalDeposited(USDC),
            first + second,
            "totalDeposited should sum"
        );
    }

    // ========================= SparkRewards Claiming (by Client) =========================

    /// @notice Client claims SPK rewards from SparkRewards merkle contract
    function test_sparkVault_claimSparkRewards_byClient() external {
        _upgradeOperatorChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        uint256 claimAmount = 1000e18;
        uint256 epoch = 1;

        _doMerkleClaim(SPARK_REWARDS, SPK, claimAmount, epoch, true);
    }

    /// @notice Client claims from Ignition Rewards
    function test_sparkVault_claimIgnitionRewards_byClient() external {
        _upgradeOperatorChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        _doMerkleClaim(IGNITION_REWARDS, SPK, 500e18, 1, true);
    }

    /// @notice Client claims from PFL3 Rewards
    function test_sparkVault_claimPfl3Rewards_byClient() external {
        _upgradeOperatorChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        _doMerkleClaim(PFL3_REWARDS, SPK, 250e18, 1, true);
    }

    // ========================= SparkRewards Claiming (by Operator) =========================

    /// @notice Operator claims SPK rewards after upgrading client-to-p2p checker
    function test_sparkVault_claimSparkRewards_byOperator() external {
        _upgradeOperatorChecker();
        _upgradeClientToP2pChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        uint256 claimAmount = 1000e18;
        uint256 epoch = 1;

        _doMerkleClaim(SPARK_REWARDS, SPK, claimAmount, epoch, false);
    }

    // ========================= SparkRewards Negative Tests =========================

    /// @notice Before checker upgrade: claim reverts with deny-all
    function test_sparkVault_claimRewards_revertsByDefault() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        bytes32[] memory proof = new bytes32[](0);
        bytes memory claimCalldata = abi.encodeCall(
            ISparkRewards.claim,
            (1, proxyAddress, SPK, 100e18, bytes32(0), proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = SPK;

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_REWARDS, claimCalldata, tokens
        );
    }

    /// @notice Nobody (not client or operator) cannot claim
    function test_sparkVault_claimRewards_revertForNobody() external {
        _upgradeOperatorChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        bytes32[] memory proof = new bytes32[](0);
        bytes memory claimCalldata = abi.encodeCall(
            ISparkRewards.claim,
            (1, proxyAddress, SPK, 100e18, bytes32(0), proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = SPK;

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__CallerNeitherClientNorP2pOperator.selector, nobody));
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(
            SPARK_REWARDS, claimCalldata, tokens
        );
    }

    /// @notice Unknown target reverts even after checker upgrade
    function test_sparkVault_claimRewards_unknownTarget_reverts() external {
        _upgradeOperatorChecker();

        deal(USDC, client, 10_000e6);
        _doDeposit(SPARK_USDC_VAULT, 10_000e6);

        bytes32[] memory proof = new bytes32[](0);
        bytes memory claimCalldata = abi.encodeCall(
            ISparkRewards.claim,
            (1, proxyAddress, SPK, 100e18, bytes32(0), proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = SPK;

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(
            makeAddr("unknownTarget"), claimCalldata, tokens
        );
    }

    // ========================= Full Flow =========================

    /// @notice Full lifecycle: deposit → accrue yield → operator takes rewards →
    ///   client claims SparkRewards → client withdraws principal
    function test_sparkVault_fullFlow() external {
        _upgradeOperatorChecker();

        uint256 depositAmt = 200_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(SPARK_USDC_VAULT, depositAmt);

        // 1. Accrue yield via SSR
        vm.warp(block.timestamp + 365 days);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(SPARK_USDC_VAULT, USDC);
        assertGt(accrued, 0, "should have accrued yield");

        // 2. Operator withdraws accrued rewards
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(SPARK_USDC_VAULT);

        // 3. Client claims SparkRewards (SPK)
        uint256 spkAmount = 500e18;
        _doMerkleClaim(SPARK_REWARDS, SPK, spkAmount, 1, true);

        // 4. Client withdraws principal
        uint256 remainingShares = IERC20(SPARK_USDC_VAULT).balanceOf(proxyAddress);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(client);
        proxy.withdraw(SPARK_USDC_VAULT, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, depositAmt - 10, "client should recover principal");
    }

    // ========================= Helpers =========================

    function _doDeposit(address _vault, uint256 _amount) private {
        address asset = IERC4626(_vault).asset();

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, _vault, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }

    /// @param _asClient true = client claims, false = operator claims
    function _doMerkleClaim(
        address _rewardsContract,
        address _token,
        uint256 _claimAmount,
        uint256 _epoch,
        bool _asClient
    ) private {
        // Build merkle tree
        bytes32 leaf = _sparkRewardsLeaf(_epoch, proxyAddress, _token, _claimAmount);
        bytes32 sibling = _sparkRewardsLeaf(_epoch, address(0xdead), _token, 1);
        bytes32 root = _merkleRoot(leaf, sibling);

        // Plant root and fund wallet
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

        if (_asClient) {
            vm.prank(client);
        } else {
            vm.prank(p2pOperator);
        }
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(
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
}
