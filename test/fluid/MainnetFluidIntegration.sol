// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/mocks/IFToken.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetFluidIntegration
/// @notice End-to-end mainnet fork tests for P2pErc4626Proxy (replacing P2pFluidProxy) covering fUSDC, fUSDT, and fWETH.
///   Fluid fTokens are standard ERC-4626 lending vaults with instant deposit/withdrawal.
///   Yield comes from lending interest + rewards rate model (reflected in exchange price).
contract MainnetFluidIntegration is Test {
    using SafeERC20 for IERC20;

    // Fluid fTokens (ERC-4626)
    address constant F_USDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
    address constant F_USDT = 0x5C20B550819128074FD538Edf79791733ccEdd18;
    address constant F_WETH = 0x90551c1795392094FE6D29B758EcCD233cFAa260;

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
    address private referenceFluid;

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

        referenceFluid = address(
            new P2pErc4626Proxy(
                address(factory), P2P_TREASURY,
                address(operatorChecker), address(clientToP2pChecker)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceFluid);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceFluid, client, CLIENT_BPS);
    }

    // ==================== fUSDC: Deposit ====================

    function test_fluid_deposit_fUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        uint256 shares = IERC20(F_USDC).balanceOf(proxyAddress);
        assertGt(shares, 0, "proxy should hold fUSDC shares");

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), USDC_DEPOSIT, "totalDeposited should match");
    }

    // ==================== fUSDC: Full Lifecycle ====================

    function test_fluid_happyPath_fUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        uint256 shares = IERC20(F_USDC).balanceOf(proxyAddress);
        assertGt(shares, 0);

        // Client redeems — instant, no queue
        uint256 clientBalBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, shares);

        uint256 clientReceived = IERC20(USDC).balanceOf(client) - clientBalBefore;
        uint256 treasuryReceived = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBalBefore;

        assertGe(clientReceived + treasuryReceived, USDC_DEPOSIT - 2, "total redeemed should be ~= deposit");
        assertLe(treasuryReceived, 1, "no yield so no fee");
    }

    // ==================== fUSDC: Yield Accrual + Fee Split ====================

    function test_fluid_accruedRewards_feeSplit_fUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        // Simulate yield: warp time to let lending interest accrue
        _simulateYield(F_USDC);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(F_USDC, USDC);
        assertGt(accrued, 0, "should have accrued rewards after yield");

        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(F_USDC);

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

    // ==================== fUSDC: Principal Protection ====================

    function test_fluid_principalProtection_fUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        // Simulate yield: warp time to let lending interest accrue
        _simulateYield(F_USDC);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);

        // Operator takes accrued rewards
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(F_USDC);

        // Client withdraws remaining principal
        uint256 remainingShares = IERC20(F_USDC).balanceOf(proxyAddress);
        assertGt(remainingShares, 0, "client should still have shares");

        uint256 clientBefore = IERC20(USDC).balanceOf(client);
        vm.prank(client);
        proxy.withdraw(F_USDC, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, USDC_DEPOSIT - 2, "client should recover principal");
    }

    // ==================== Access Control ====================

    function test_fluid_onlyClient_canWithdraw() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        uint256 shares = IERC20(F_USDC).balanceOf(proxyAddress);

        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, shares);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, shares);
    }

    function test_fluid_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        _simulateYield(F_USDC);

        vm.prank(client);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ==================== fUSDT: Deposit + Withdraw ====================

    function test_fluid_deposit_fUSDT() external {
        deal(USDT, client, USDT_DEPOSIT);

        // USDT requires special handling for approve (no return value)
        vm.startPrank(client);
        (bool success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", proxyAddress, USDT_DEPOSIT));
        require(success, "USDT approve failed");
        vm.stopPrank();

        bytes32 hash = factory.getHashForP2pSigner(referenceFluid, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        factory.deposit(referenceFluid, F_USDT, USDT_DEPOSIT, CLIENT_BPS, block.timestamp + 1 hours, sig);

        uint256 shares = IERC20(F_USDT).balanceOf(proxyAddress);
        assertGt(shares, 0, "proxy should hold fUSDT shares");
    }

    // ==================== fWETH: Deposit + Withdraw ====================

    function test_fluid_happyPath_fWETH() external {
        deal(WETH, client, WETH_DEPOSIT);

        _doDeposit(F_WETH, WETH_DEPOSIT);

        uint256 shares = IERC20(F_WETH).balanceOf(proxyAddress);
        assertGt(shares, 0, "proxy should hold fWETH shares");

        // Withdraw
        uint256 clientBefore = IERC20(WETH).balanceOf(client);

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(F_WETH, shares);

        uint256 clientReceived = IERC20(WETH).balanceOf(client) - clientBefore;
        assertGe(clientReceived, WETH_DEPOSIT - 2, "client should recover WETH");
    }

    // ==================== Multiple Deposits ====================

    function test_fluid_multipleDeposits_fUSDC() external {
        uint256 firstDeposit = 50_000e6;
        uint256 secondDeposit = 30_000e6;
        deal(USDC, client, firstDeposit + secondDeposit);

        _doDeposit(F_USDC, firstDeposit);
        uint256 sharesAfterFirst = IERC20(F_USDC).balanceOf(proxyAddress);
        assertGt(sharesAfterFirst, 0);

        _doDeposit(F_USDC, secondDeposit);
        uint256 sharesAfterSecond = IERC20(F_USDC).balanceOf(proxyAddress);
        assertGt(sharesAfterSecond, sharesAfterFirst);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        assertEq(proxy.getTotalDeposited(USDC), firstDeposit + secondDeposit, "totalDeposited should sum both");
    }

    // ==================== Zero Accrued Reverts ====================

    function test_fluid_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, USDC_DEPOSIT);

        _doDeposit(F_USDC, USDC_DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pErc4626Proxy__ZeroAccruedRewards.selector);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ==================== fToken Data View ====================

    function test_fluid_fTokenData() external view {
        (
            address liquidity_,
            address lendingFactory_,
            ,,
            address rebalancer_,
            bool rewardsActive_,
            uint256 liquidityBalance_,
            ,
            uint256 tokenExchangePrice_
        ) = IFToken(F_USDC).getData();

        assertNotEq(liquidity_, address(0), "liquidity should be set");
        assertNotEq(lendingFactory_, address(0), "lending factory should be set");
        assertNotEq(rebalancer_, address(0), "rebalancer should be set");
        assertGt(liquidityBalance_, 0, "liquidity balance should be > 0");
        assertGt(tokenExchangePrice_, 0, "token exchange price should be > 0");
        // rewardsActive_ may or may not be true at this block
    }

    // ==================== Helpers ====================

    function _doDeposit(address _fToken, uint256 _amount) internal {
        address asset = IERC4626(_fToken).asset();

        vm.startPrank(client);
        IERC20(asset).safeIncreaseAllowance(proxyAddress, _amount);
        vm.stopPrank();

        bytes32 hash = factory.getHashForP2pSigner(referenceFluid, client, CLIENT_BPS, block.timestamp + 1 hours);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, _toEthSignedHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(client);
        address addr = factory.deposit(referenceFluid, _fToken, _amount, CLIENT_BPS, block.timestamp + 1 hours, sig);

        assertEq(addr, proxyAddress, "proxy address mismatch");
    }

    function _toEthSignedHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @dev Fluid exchange price comes from the Liquidity layer, not from fToken balance.
    ///   Warp time forward so lending interest accrues, then call updateRates() to refresh the exchange price.
    function _simulateYield(address _fToken) internal {
        vm.warp(block.timestamp + 365 days);
        IFToken(_fToken).updateRates();
    }
}
