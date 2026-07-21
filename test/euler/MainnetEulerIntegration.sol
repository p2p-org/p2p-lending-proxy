// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/euler/@euler/IEVault.sol";
import "../../src/adapters/euler/@euler/IEVC.sol";
import "../../src/adapters/euler/@euler/ITrackingRewardStreams.sol";
import "../../src/adapters/euler/p2pEulerProxy/P2pEulerProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetEulerIntegration
/// @notice End-to-end Ethereum mainnet fork tests for P2pEulerProxy with eUSDC-2, eUSDT-2, eWETH-2.
///   Euler EVaults are ERC-4626 lending vaults that require routing through the EVC.
///   Yield accrues from lending interest (via interest rate model).
///   Additional rewards accrue through Reward Streams (TrackingRewardStreams).
contract MainnetEulerIntegration is Test {
    using SafeERC20 for IERC20;

    // Euler EVaults on Ethereum mainnet
    address constant E_USDC = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9; // eUSDC-2
    address constant E_USDT = 0x313603FA690301b0CaeEf8069c065862f9162162; // eUSDT-2
    address constant E_WETH = 0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2; // eWETH-2

    // Underlying tokens
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Euler protocol contracts
    address constant EVC = 0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383;
    address constant REWARD_STREAMS = 0x0D52d06ceB8Dcdeeb40Cfd9f17489B350dD7F8a3;

    // EUL token
    address constant EUL = 0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceEuler;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;

    address private proxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(rpc);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        ProxyAdmin a1 = new ProxyAdmin();
        TransparentUpgradeableProxy opChecker =
            new TransparentUpgradeableProxy(address(checkerImpl), address(a1), initData);

        ProxyAdmin a2 = new ProxyAdmin();
        TransparentUpgradeableProxy c2pChecker =
            new TransparentUpgradeableProxy(address(checkerImpl), address(a2), initData);

        factory = new P2pYieldProxyFactory(p2pSigner);

        referenceEuler = address(
            new P2pEulerProxy(
                address(factory),
                P2P_TREASURY,
                address(opChecker),
                address(c2pChecker),
                EVC
            )
        );
        factory.addReferenceP2pYieldProxy(referenceEuler);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceEuler, client, CLIENT_BPS);
    }

    // ==================== eUSDC: Deposit + Withdraw ====================

    function test_euler_deposit_withdraw_eUSDC() external {
        _depositAndWithdraw(E_USDC, USDC, 10_000e6);
    }

    // ==================== eUSDC: Yield Accrual + Fee Split ====================

    function test_euler_yieldAccrual_eUSDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(E_USDC, depositAmt);

        _simulateYield();

        P2pEulerProxy proxy = P2pEulerProxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(E_USDC, USDC);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(E_USDC);

        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGt(treasuryDelta + clientDelta, 0, "should have distributed rewards");
        assertGt(treasuryDelta, 0, "treasury should receive fee");
    }

    // ==================== eUSDC: Principal Protection ====================

    function test_euler_principalProtection_eUSDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(E_USDC, depositAmt);

        _simulateYield();

        vm.prank(p2pOperator);
        P2pEulerProxy(proxyAddress).withdrawAccruedRewards(E_USDC);

        uint256 remainingShares = IERC20(E_USDC).balanceOf(proxyAddress);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(client);
        P2pEulerProxy(proxyAddress).withdraw(E_USDC, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, depositAmt - 2, "client should recover principal");
    }

    // ==================== eUSDT: Deposit + Withdraw ====================

    function test_euler_deposit_withdraw_eUSDT() external {
        _depositAndWithdraw(E_USDT, USDT, 10_000e6);
    }

    // ==================== eUSDT: Yield Accrual ====================

    function test_euler_yieldAccrual_eUSDT() external {
        uint256 depositAmt = 50_000e6;
        deal(USDT, client, depositAmt);
        _doDeposit(E_USDT, depositAmt);

        _simulateYield();

        P2pEulerProxy proxy = P2pEulerProxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(E_USDT, USDT);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDT).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(E_USDT);

        assertGt(IERC20(USDT).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ==================== eWETH: Deposit + Withdraw ====================

    function test_euler_deposit_withdraw_eWETH() external {
        _depositAndWithdraw(E_WETH, WETH, 10e18);
    }

    // ==================== eWETH: Yield Accrual ====================

    function test_euler_yieldAccrual_eWETH() external {
        uint256 depositAmt = 50e18;
        deal(WETH, client, depositAmt);
        _doDeposit(E_WETH, depositAmt);

        _simulateYield();

        P2pEulerProxy proxy = P2pEulerProxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(E_WETH, WETH);
        assertGt(accrued, 0, "should have accrued WETH rewards");

        uint256 treasuryBefore = IERC20(WETH).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(E_WETH);

        assertGt(IERC20(WETH).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ==================== Access Control ====================

    function test_euler_onlyClient_canWithdraw() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(E_USDC, 10_000e6);

        uint256 shares = IERC20(E_USDC).balanceOf(proxyAddress);

        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pEulerProxy(proxyAddress).withdraw(E_USDC, shares);

        vm.prank(nobody);
        vm.expectRevert();
        P2pEulerProxy(proxyAddress).withdraw(E_USDC, shares);
    }

    function test_euler_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, 100_000e6);
        _doDeposit(E_USDC, 100_000e6);

        _simulateYield();

        vm.prank(client);
        vm.expectRevert();
        P2pEulerProxy(proxyAddress).withdrawAccruedRewards(E_USDC);

        vm.prank(nobody);
        vm.expectRevert();
        P2pEulerProxy(proxyAddress).withdrawAccruedRewards(E_USDC);
    }

    // ==================== Zero Accrued Reverts ====================

    function test_euler_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(E_USDC, 10_000e6);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pEulerProxy__ZeroAccruedRewards.selector);
        P2pEulerProxy(proxyAddress).withdrawAccruedRewards(E_USDC);
    }

    // ==================== Balance Forwarder ====================

    function test_euler_enableBalanceForwarder() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(E_USDC, 10_000e6);

        // Verify not enabled yet
        bool enabledBefore = IEVault(E_USDC).balanceForwarderEnabled(proxyAddress);
        assertFalse(enabledBefore, "balance forwarder should be disabled initially");

        // Client enables balance forwarder
        vm.prank(client);
        P2pEulerProxy(proxyAddress).enableBalanceForwarder(E_USDC);

        bool enabledAfter = IEVault(E_USDC).balanceForwarderEnabled(proxyAddress);
        assertTrue(enabledAfter, "balance forwarder should be enabled");

        // Verify tracked balance in reward streams
        uint256 shares = IERC20(E_USDC).balanceOf(proxyAddress);
        uint256 trackedBalance = ITrackingRewardStreams(REWARD_STREAMS).balanceOf(proxyAddress, E_USDC);
        assertEq(trackedBalance, shares, "tracked balance should match shares");
    }

    // ==================== Enable Reward ====================

    function test_euler_enableReward() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(E_USDC, 10_000e6);

        // Enable balance forwarder first
        vm.prank(client);
        P2pEulerProxy(proxyAddress).enableBalanceForwarder(E_USDC);

        // Enable EUL reward
        vm.prank(p2pOperator);
        P2pEulerProxy(proxyAddress).enableReward(E_USDC, EUL);

        address[] memory enabled = ITrackingRewardStreams(REWARD_STREAMS).enabledRewards(proxyAddress, E_USDC);
        assertEq(enabled.length, 1, "should have 1 enabled reward");
        assertEq(enabled[0], EUL, "enabled reward should be EUL");
    }

    // ==================== Multiple Deposits ====================

    function test_euler_multipleDeposits_eUSDC() external {
        uint256 firstDeposit = 50_000e6;
        uint256 secondDeposit = 30_000e6;
        deal(USDC, client, firstDeposit + secondDeposit);

        _doDeposit(E_USDC, firstDeposit);
        uint256 sharesAfterFirst = IERC20(E_USDC).balanceOf(proxyAddress);
        assertGt(sharesAfterFirst, 0);

        _doDeposit(E_USDC, secondDeposit);
        uint256 sharesAfterSecond = IERC20(E_USDC).balanceOf(proxyAddress);
        assertGt(sharesAfterSecond, sharesAfterFirst);

        P2pEulerProxy proxy = P2pEulerProxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), firstDeposit + secondDeposit, "totalDeposited should sum both");
    }

    // ==================== supportsInterface ====================

    function test_euler_supportsInterface() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(E_USDC, 10_000e6);

        P2pEulerProxy proxy = P2pEulerProxy(proxyAddress);
        assertTrue(proxy.supportsInterface(type(IP2pEulerProxy).interfaceId), "should support IP2pEulerProxy");
    }

    // ==================== Helpers ====================

    function _depositAndWithdraw(address _vault, address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doDeposit(_vault, _amount);

        uint256 shares = IERC20(_vault).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold eToken shares");

        vm.prank(client);
        P2pEulerProxy(proxyAddress).withdraw(_vault, shares);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _doDeposit(address _vault, uint256 _amount) private {
        address asset = IEVault(_vault).asset();

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceEuler, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceEuler, _vault, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }

    /// @dev Warp time forward to let lending interest accrue.
    /// EVaults accrue interest based on the interest rate model + utilization.
    function _simulateYield() private {
        vm.warp(block.timestamp + 365 days);
    }
}
