// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/aave/@aave/IAaveV3Pool.sol";
import "../../src/adapters/spark/p2pSparkProxy/P2pSparkProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetSparkIntegration
/// @notice End-to-end mainnet fork tests for P2pSparkProxy covering USDC, USDT, and WETH.
///   SparkLend is an Aave V3 fork with identical Pool interface.
///   Yield comes from lending interest (spToken balance grows via rebasing).
///   SPK token rewards are distributed via a separate SparkRewards merkle contract.
contract MainnetSparkIntegration is Test {
    using SafeERC20 for IERC20;

    // SparkLend core
    address constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address constant SPARK_DATA_PROVIDER = 0xFc21d6d146E6086B8359705C8b28512a983db0cb;

    // Underlying tokens
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;

    uint96 constant CLIENT_BPS = 9_000; // client keeps 90%, P2P takes 10%
    uint256 constant USDC_DEPOSIT = 100_000e6;
    uint256 constant USDT_DEPOSIT = 50_000e6;
    uint256 constant WETH_DEPOSIT = 50e18;

    P2pYieldProxyFactory private factory;
    address private referenceSpark;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;

    address private proxyAddress;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(mainnetRpc, 21_308_893);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        ProxyAdmin operatorAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy operatorChecker = new TransparentUpgradeableProxy(
            address(checkerImpl), address(operatorAdmin), initData
        );

        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pChecker = new TransparentUpgradeableProxy(
            address(checkerImpl), address(clientToP2pAdmin), initData
        );

        factory = new P2pYieldProxyFactory(p2pSigner);

        referenceSpark = address(
            new P2pSparkProxy(
                address(factory), P2P_TREASURY,
                address(operatorChecker), address(clientToP2pChecker),
                SPARK_POOL, SPARK_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceSpark);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceSpark, client, CLIENT_BPS);
    }

    // ==================== USDC: Deposit ====================

    function test_spark_deposit_USDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        assertGt(IERC20(spToken).balanceOf(proxyAddress), 0, "proxy should hold spUSDC");

        P2pSparkProxy proxy = P2pSparkProxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), USDC_DEPOSIT, "totalDeposited should match");
    }

    // ==================== USDC: Full Lifecycle ====================

    function test_spark_happyPath_USDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        vm.recordLogs();
        _doDeposit(USDC, USDC_DEPOSIT);
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertSparkEventSeen(depositLogs, keccak256("Supply(address,address,address,uint256,uint16)"));

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        assertGt(IERC20(spToken).balanceOf(proxyAddress), 0);

        // Client withdraws all — instant, no queue
        vm.recordLogs();
        vm.prank(client);
        P2pSparkProxy(proxyAddress).withdraw(USDC, type(uint256).max);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertSparkEventSeen(withdrawLogs, keccak256("Withdraw(address,address,address,uint256)"));

        assertEq(IERC20(spToken).balanceOf(proxyAddress), 0, "spToken balance should be 0");
    }

    // ==================== USDC: Yield Accrual + Fee Split ====================

    function test_spark_accruedRewards_feeSplit_USDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        // Simulate yield: supply extra USDC on behalf of the proxy (like Aave test pattern)
        _simulateYield(USDC, 5_000e6);

        P2pSparkProxy proxy = P2pSparkProxy(proxyAddress);
        address spToken = proxy.getSpToken(USDC);
        int256 accrued = proxy.calculateAccruedRewards(spToken, USDC);
        assertGt(accrued, 0, "should have accrued rewards after yield");

        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(USDC);

        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;
        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 totalDistributed = clientDelta + treasuryDelta;

        assertGt(totalDistributed, 0, "should have distributed rewards");

        // Verify fee split: treasury gets (1-clientBps)/10000 of profit, ceiling div
        uint256 expectedP2p = (totalDistributed * (10_000 - CLIENT_BPS) + 9999) / 10_000;
        assertApproxEqAbs(treasuryDelta, expectedP2p, 1, "treasury fee should match");

        uint256 expectedClient = totalDistributed - expectedP2p;
        assertApproxEqAbs(clientDelta, expectedClient, 1, "client share should match");
    }

    // ==================== USDC: Principal Protection ====================

    function test_spark_principalProtection_USDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        // Simulate yield
        _simulateYield(USDC, 10_000e6);

        P2pSparkProxy proxy = P2pSparkProxy(proxyAddress);

        // Operator takes accrued rewards
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(USDC);

        // Client withdraws remaining principal
        address spToken = proxy.getSpToken(USDC);
        uint256 remainingBalance = IERC20(spToken).balanceOf(proxyAddress);
        assertGt(remainingBalance, 0, "client should still have spTokens");

        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        vm.prank(client);
        proxy.withdraw(USDC, type(uint256).max);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, USDC_DEPOSIT - 2, "client should recover principal");
    }

    // ==================== Access Control ====================

    function test_spark_onlyClient_canWithdraw() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pSparkProxy(proxyAddress).withdraw(USDC, type(uint256).max);

        vm.prank(nobody);
        vm.expectRevert();
        P2pSparkProxy(proxyAddress).withdraw(USDC, type(uint256).max);
    }

    function test_spark_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        _simulateYield(USDC, 5_000e6);

        vm.prank(client);
        vm.expectRevert();
        P2pSparkProxy(proxyAddress).withdrawAccruedRewards(USDC);

        vm.prank(nobody);
        vm.expectRevert();
        P2pSparkProxy(proxyAddress).withdrawAccruedRewards(USDC);
    }

    // ==================== USDT: Deposit + Withdraw ====================

    function test_spark_deposit_USDT() external {
        deal(USDT, client, USDT_DEPOSIT);

        // USDT requires special handling for approve (no return value)
        vm.startPrank(client);
        (bool success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", proxyAddress, USDT_DEPOSIT));
        require(success, "USDT approve failed");
        vm.stopPrank();

        bytes32 hash = factory.getHashForP2pSigner(referenceSpark, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        factory.deposit(referenceSpark, USDT, USDT_DEPOSIT, CLIENT_BPS, block.timestamp + 1 hours, sig);

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDT);
        assertGt(IERC20(spToken).balanceOf(proxyAddress), 0, "proxy should hold spUSDT");
    }

    // ==================== WETH: Deposit + Withdraw ====================

    function test_spark_happyPath_WETH() external {
        deal(WETH, client, WETH_DEPOSIT);

        _doDeposit(WETH, WETH_DEPOSIT);

        address spToken = P2pSparkProxy(proxyAddress).getSpToken(WETH);
        assertGt(IERC20(spToken).balanceOf(proxyAddress), 0, "proxy should hold spWETH");

        // Withdraw
        uint256 clientBefore = IERC20(WETH).balanceOf(client);

        vm.prank(client);
        P2pSparkProxy(proxyAddress).withdraw(WETH, type(uint256).max);

        uint256 clientReceived = IERC20(WETH).balanceOf(client) - clientBefore;
        assertGe(clientReceived, WETH_DEPOSIT - 2, "client should recover WETH");
    }

    // ==================== Multiple Deposits ====================

    function test_spark_multipleDeposits_USDC() external {
        uint256 firstDeposit = 50_000e6;
        uint256 secondDeposit = 30_000e6;
        deal(USDC, client, firstDeposit + secondDeposit);

        _doDeposit(USDC, firstDeposit);
        address spToken = P2pSparkProxy(proxyAddress).getSpToken(USDC);
        uint256 balanceAfterFirst = IERC20(spToken).balanceOf(proxyAddress);
        assertGt(balanceAfterFirst, 0);

        _doDeposit(USDC, secondDeposit);
        uint256 balanceAfterSecond = IERC20(spToken).balanceOf(proxyAddress);
        assertGt(balanceAfterSecond, balanceAfterFirst);

        P2pSparkProxy proxy = P2pSparkProxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), firstDeposit + secondDeposit, "totalDeposited should sum both");
    }

    // ==================== Zero Accrued Reverts ====================

    function test_spark_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(USDC, USDC_DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pSparkProxy__ZeroAccruedRewards.selector);
        P2pSparkProxy(proxyAddress).withdrawAccruedRewards(USDC);
    }

    // ==================== spToken View ====================

    function test_spark_spToken_addresses() external {
        // Deploy the proxy by making a deposit first
        deal(USDC, client, USDC_DEPOSIT);
        _doDeposit(USDC, USDC_DEPOSIT);

        P2pSparkProxy proxy = P2pSparkProxy(proxyAddress);
        address spUSDC = proxy.getSpToken(USDC);
        address spUSDT = proxy.getSpToken(USDT);
        address spWETH = proxy.getSpToken(WETH);

        assertEq(spUSDC, 0x377C3bd93f2a2984E1E7bE6A5C22c525eD4A4815, "spUSDC address mismatch");
        assertEq(spUSDT, 0xe7dF13b8e3d6740fe17CBE928C7334243d86c92f, "spUSDT address mismatch");
        assertEq(spWETH, 0x59cD1C87501baa753d0B5B5Ab5D8416A45cD71DB, "spWETH address mismatch");
    }

    // ==================== Helpers ====================

    function _doDeposit(address _asset, uint256 _amount) internal {
        vm.startPrank(client);
        IERC20(_asset).safeIncreaseAllowance(proxyAddress, _amount);
        vm.stopPrank();

        bytes32 hash = factory.getHashForP2pSigner(referenceSpark, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        address addr = factory.deposit(referenceSpark, _asset, _amount, CLIENT_BPS, block.timestamp + 1 hours, sig);

        assertEq(addr, proxyAddress, "proxy address mismatch");
    }

    function _toEthSignedHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @dev Simulate yield by supplying extra tokens on behalf of the proxy (same pattern as Aave tests).
    ///   spTokens are rebasing — balance grows with supply interest. For testing, we supply
    ///   extra from a donor to directly increase the proxy's spToken balance.
    function _simulateYield(address _asset, uint256 _yieldAmount) internal {
        address donor = makeAddr("donor");
        deal(_asset, donor, _yieldAmount);
        vm.startPrank(donor);
        IERC20(_asset).safeApprove(SPARK_POOL, _yieldAmount);
        IAaveV3Pool(SPARK_POOL).supply(_asset, _yieldAmount, proxyAddress, 0);
        vm.stopPrank();
    }

    function _assertSparkEventSeen(Vm.Log[] memory _logs, bytes32 _eventSig) private pure {
        uint256 logsLength = _logs.length;
        for (uint256 i; i < logsLength; ++i) {
            Vm.Log memory log = _logs[i];
            if (log.emitter == SPARK_POOL && log.topics.length > 0 && log.topics[0] == _eventSig) {
                return;
            }
        }
        revert("SPARK_EVENT_NOT_FOUND");
    }
}
