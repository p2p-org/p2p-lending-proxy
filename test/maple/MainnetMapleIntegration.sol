// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/maple/@maple/IMaplePool.sol";
import "../../src/adapters/maple/@maple/IMaplePoolManager.sol";
import "../../src/adapters/maple/@maple/IMaplePoolPermissionManager.sol";
import "../../src/adapters/maple/@maple/IWithdrawalManagerQueue.sol";
import "../../src/adapters/maple/p2pMapleProxy/P2pMapleProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetMapleIntegration
/// @notice End-to-end mainnet fork tests for P2pMapleProxy covering syrupUSDC and syrupUSDT.
///   Maple uses a FIFO WithdrawalManagerQueue with two modes:
///   - Automatic (default): processRedemptions directly redeems and sends assets to the owner.
///   - Manual: processRedemptions records manualSharesAvailable, owner calls pool.redeem() separately.
///   P2pMapleProxy.withdraw() calls pool.redeem(), so the proxy MUST be in manual withdrawal mode.
contract MainnetMapleIntegration is Test {
    using SafeERC20 for IERC20;

    // Maple pools (ERC-4626)
    address constant SYRUP_USDC_POOL = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address constant SYRUP_USDT_POOL = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    // Maple pool managers
    address constant SYRUP_USDC_POOL_MANAGER = 0x7aD5fFa5fdF509E30186F4609c2f6269f4B6158F;
    address constant SYRUP_USDT_POOL_MANAGER = 0x0cdA32E08B48bFDDbc7eE96B44b09cf286F9E21a;

    // Maple withdrawal manager queues
    address constant SYRUP_USDC_WM = 0x1bc47a0Dd0FdaB96E9eF982fdf1F34DC6207cfE3;
    address constant SYRUP_USDT_WM = 0x86eBDf902d800F2a82038290B6DBb2A5eE29eB8C;

    // Underlying tokens
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Maple permission manager
    address constant POOL_PERMISSION_MANAGER = 0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3;

    // Maple globals + governor (for impersonation)
    address constant MAPLE_GOVERNOR = 0x2eFFf88747EB5a3FF00d4d8d0f0800E306C0426b;
    address constant PERMISSIONS_ADMIN = 0x54b130c704919320E17F4F1Ffa4832A91AB29Dca;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;

    uint96 constant CLIENT_BPS = 8_700; // client keeps 87%, P2P takes 13%
    uint256 constant USDC_DEPOSIT = 100_000e6; // 100k USDC
    uint256 constant USDT_DEPOSIT = 50_000e6;  // 50k USDT

    // Bitmap bit 4 required for syrupUSDC deposit
    uint256 constant DEPOSIT_BITMAP = 0x10;

    P2pYieldProxyFactory private factory;
    address private referenceMaple;

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

        referenceMaple = address(
            new P2pMapleProxy(
                address(factory), P2P_TREASURY,
                address(operatorChecker), address(clientToP2pChecker)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceMaple);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceMaple, client, CLIENT_BPS);

        // Grant Maple deposit permission to the proxy address
        _grantMaplePermission(proxyAddress);

        // Set manual withdrawal mode for the proxy on both pools.
        // This is required because P2pMapleProxy.withdraw() calls pool.redeem(),
        // which only works when processRedemptions has recorded manualSharesAvailable.
        _setManualWithdrawal(SYRUP_USDC_POOL_MANAGER, SYRUP_USDC_WM, proxyAddress);
        _setManualWithdrawal(SYRUP_USDT_POOL_MANAGER, SYRUP_USDT_WM, proxyAddress);
    }

    // ==================== syrupUSDC: Deposit ====================

    function test_maple_deposit_syrupUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        uint256 shares = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertGt(shares, 0, "proxy should hold syrupUSDC shares");

        P2pMapleProxy proxy = P2pMapleProxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), USDC_DEPOSIT, "totalDeposited should match");
    }

    // ==================== syrupUSDC: Full Lifecycle ====================

    function test_maple_happyPath_syrupUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        uint256 shares = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertGt(shares, 0);

        // Request redeem
        vm.prank(client);
        P2pMapleProxy(proxyAddress).requestRedeem(SYRUP_USDC_POOL, shares);

        // Verify a request was created
        uint256 requestId = IWithdrawalManagerQueue(SYRUP_USDC_WM).requestIds(proxyAddress);
        assertGt(requestId, 0, "request should be created in withdrawal queue");

        // Pool delegate processes redemptions (manual mode: records manualSharesAvailable)
        _processRedemptions(SYRUP_USDC_POOL_MANAGER, SYRUP_USDC_WM, shares);

        // After processing, lockedShares (== manualSharesAvailable) should be > 0
        uint256 manualAvail = IWithdrawalManagerQueue(SYRUP_USDC_WM).lockedShares(proxyAddress);
        assertGt(manualAvail, 0, "manualSharesAvailable should be set after processing");

        // Client redeems via proxy.withdraw → pool.redeem
        uint256 clientBalBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(client);
        P2pMapleProxy(proxyAddress).withdraw(SYRUP_USDC_POOL, shares);

        uint256 clientReceived = IERC20(USDC).balanceOf(client) - clientBalBefore;
        uint256 treasuryReceived = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBalBefore;

        // Client should receive at least the deposit minus some rounding
        assertGe(clientReceived + treasuryReceived, USDC_DEPOSIT - 2, "total redeemed should be ~= deposit");
        // Treasury gets 0 or near-zero since no yield accrued
        assertLe(treasuryReceived, 1, "no yield so no fee");
    }

    // ==================== syrupUSDC: Yield Accrual + Fee Split ====================

    function test_maple_accruedRewards_feeSplit_syrupUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        // Simulate yield: deal extra USDC to the pool to increase share value
        uint256 yieldAmount = 5_000e6; // 5k USDC yield
        _simulateYield(SYRUP_USDC_POOL, USDC, yieldAmount);

        P2pMapleProxy proxy = P2pMapleProxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(SYRUP_USDC_POOL, USDC);
        assertGt(accrued, 0, "should have accrued rewards after yield");

        // Operator requests redeem for accrued rewards
        vm.prank(p2pOperator);
        uint256 escrowed = proxy.requestRedeemAccruedRewards(SYRUP_USDC_POOL);
        assertGt(escrowed, 0, "accrued shares should be escrowed");

        // Process the escrowed shares (manual mode)
        _processRedemptions(SYRUP_USDC_POOL_MANAGER, SYRUP_USDC_WM, escrowed);

        // Operator withdraws accrued rewards
        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(SYRUP_USDC_POOL);

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

    // ==================== syrupUSDC: Principal Protection ====================

    function test_maple_principalProtection_syrupUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        // Simulate yield
        _simulateYield(SYRUP_USDC_POOL, USDC, 10_000e6);

        P2pMapleProxy proxy = P2pMapleProxy(proxyAddress);

        // Operator takes accrued rewards
        vm.prank(p2pOperator);
        uint256 accruedEscrowed = proxy.requestRedeemAccruedRewards(SYRUP_USDC_POOL);
        _processRedemptions(SYRUP_USDC_POOL_MANAGER, SYRUP_USDC_WM, accruedEscrowed);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(SYRUP_USDC_POOL);

        // Client withdraws remaining principal
        uint256 remainingShares = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertGt(remainingShares, 0, "client should still have shares");

        vm.prank(client);
        proxy.requestRedeem(SYRUP_USDC_POOL, remainingShares);
        _processRedemptions(SYRUP_USDC_POOL_MANAGER, SYRUP_USDC_WM, remainingShares);

        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        vm.prank(client);
        proxy.withdraw(SYRUP_USDC_POOL, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;

        // Client should get back at least the deposit amount (residual yield may remain)
        assertGe(clientPrincipal, USDC_DEPOSIT - 2, "client should recover principal");
    }

    // ==================== Access Control ====================

    function test_maple_onlyClient_canWithdraw() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        uint256 shares = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);

        // Operator cannot call withdraw
        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).withdraw(SYRUP_USDC_POOL, shares);

        // Nobody cannot call withdraw
        vm.prank(nobody);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).withdraw(SYRUP_USDC_POOL, shares);

        // Only client can request redeem
        vm.prank(nobody);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).requestRedeem(SYRUP_USDC_POOL, shares);
    }

    function test_maple_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        _simulateYield(SYRUP_USDC_POOL, USDC, 5_000e6);

        // Client cannot call withdrawAccruedRewards
        vm.prank(client);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).withdrawAccruedRewards(SYRUP_USDC_POOL);

        // Nobody cannot call withdrawAccruedRewards
        vm.prank(nobody);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).withdrawAccruedRewards(SYRUP_USDC_POOL);

        // Client cannot call requestRedeemAccruedRewards
        vm.prank(client);
        vm.expectRevert();
        P2pMapleProxy(proxyAddress).requestRedeemAccruedRewards(SYRUP_USDC_POOL);
    }

    // ==================== syrupUSDT: Deposit ====================

    function test_maple_deposit_syrupUSDT() external {
        deal(USDT, client, USDT_DEPOSIT);

        // For USDT, same proxy (same referenceMaple + client + bps).
        // Grant permission for the proxy on USDT pool.
        _grantMaplePermission(proxyAddress);

        // USDT requires special handling for approve (no return value)
        vm.startPrank(client);
        (bool success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", proxyAddress, USDT_DEPOSIT));
        require(success, "USDT approve failed");
        vm.stopPrank();

        // Deposit via factory
        bytes32 hash = factory.getHashForP2pSigner(referenceMaple, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        factory.deposit(referenceMaple, SYRUP_USDT_POOL, USDT_DEPOSIT, CLIENT_BPS, block.timestamp + 1 hours, sig);

        uint256 shares = IERC20(SYRUP_USDT_POOL).balanceOf(proxyAddress);
        assertGt(shares, 0, "proxy should hold syrupUSDT shares");
    }

    // ==================== Multiple Deposits ====================

    function test_maple_multipleDeposits_syrupUSDC() external {
        uint256 firstDeposit = 50_000e6;
        uint256 secondDeposit = 30_000e6;
        deal(USDC, client, firstDeposit + secondDeposit);

        // First deposit
        _doDeposit(SYRUP_USDC_POOL, firstDeposit);
        uint256 sharesAfterFirst = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertGt(sharesAfterFirst, 0);

        // Second deposit
        _doDeposit(SYRUP_USDC_POOL, secondDeposit);
        uint256 sharesAfterSecond = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertGt(sharesAfterSecond, sharesAfterFirst);

        P2pMapleProxy proxy = P2pMapleProxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), firstDeposit + secondDeposit, "totalDeposited should sum both");
    }

    // ==================== Zero Accrued Reverts ====================

    function test_maple_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        // No yield simulated — accrued should be 0 or negative
        vm.prank(p2pOperator);
        vm.expectRevert(P2pMapleProxy__ZeroAccruedRewards.selector);
        P2pMapleProxy(proxyAddress).withdrawAccruedRewards(SYRUP_USDC_POOL);
    }

    function test_maple_requestRedeemAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pMapleProxy__ZeroAccruedRewards.selector);
        P2pMapleProxy(proxyAddress).requestRedeemAccruedRewards(SYRUP_USDC_POOL);
    }

    // ==================== Remove Shares ====================

    function test_maple_removeShares_cancelsRequest() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(SYRUP_USDC_POOL, USDC_DEPOSIT);

        uint256 shares = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);

        // Request redeem
        vm.prank(client);
        P2pMapleProxy(proxyAddress).requestRedeem(SYRUP_USDC_POOL, shares);

        // Verify a request was created
        uint256 requestId = IWithdrawalManagerQueue(SYRUP_USDC_WM).requestIds(proxyAddress);
        assertGt(requestId, 0, "request should exist after requestRedeem");

        // Proxy should have 0 pool shares (transferred to WM)
        uint256 sharesInProxy = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertEq(sharesInProxy, 0, "proxy should have no shares after requestRedeem");

        // Client cancels by removing shares
        vm.prank(client);
        P2pMapleProxy(proxyAddress).removeShares(SYRUP_USDC_POOL, shares);

        // Shares should be back in proxy
        uint256 sharesAfter = IERC20(SYRUP_USDC_POOL).balanceOf(proxyAddress);
        assertEq(sharesAfter, shares, "shares should return to proxy after cancel");
    }

    // ==================== Helpers ====================

    function _doDeposit(address _pool, uint256 _amount) internal {
        address asset = IMaplePool(_pool).asset();

        vm.startPrank(client);
        IERC20(asset).safeIncreaseAllowance(proxyAddress, _amount);
        vm.stopPrank();

        bytes32 hash = factory.getHashForP2pSigner(referenceMaple, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        address addr = factory.deposit(referenceMaple, _pool, _amount, CLIENT_BPS, block.timestamp + 1 hours, sig);

        assertEq(addr, proxyAddress, "proxy address mismatch");
    }

    function _toEthSignedHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _grantMaplePermission(address _lender) internal {
        vm.startPrank(PERMISSIONS_ADMIN);

        address[] memory lenders = new address[](1);
        lenders[0] = _lender;
        uint256[] memory bitmaps = new uint256[](1);
        bitmaps[0] = DEPOSIT_BITMAP;

        IMaplePoolPermissionManager(POOL_PERMISSION_MANAGER).setLenderBitmaps(lenders, bitmaps);

        vm.stopPrank();
    }

    function _simulateYield(address _pool, address _asset, uint256 _yieldAmount) internal {
        // Deal extra assets directly to the pool to simulate yield accrual.
        // This increases totalAssets and therefore the share price.
        uint256 currentBalance = IERC20(_asset).balanceOf(_pool);
        deal(_asset, _pool, currentBalance + _yieldAmount);
    }

    function _setManualWithdrawal(address _poolManager, address _wmQueue, address _owner) internal {
        address poolDelegate = IMaplePoolManager(_poolManager).poolDelegate();
        vm.prank(poolDelegate);
        IWithdrawalManagerQueue(_wmQueue).setManualWithdrawal(_owner, true);
    }

    function _processRedemptions(address _poolManager, address _wmQueue, uint256 _shares) internal {
        address poolDelegate = IMaplePoolManager(_poolManager).poolDelegate();
        vm.prank(poolDelegate);
        IWithdrawalManagerQueue(_wmQueue).processRedemptions(_shares);
    }
}
