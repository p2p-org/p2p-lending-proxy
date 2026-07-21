// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/mocks/IFToken.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title ArbitrumFluidIntegration
/// @notice Arbitrum fork tests for P2pErc4626Proxy (replacing P2pFluidProxy) with fUSDC and fUSDT.
contract ArbitrumFluidIntegration is Test {
    using SafeERC20 for IERC20;

    // Fluid fTokens on Arbitrum
    address constant F_USDC = 0x1A996cb54bb95462040408C06122D45D6Cdb6096;
    address constant F_USDT = 0x4A03F37e7d3fC243e3f99341d36f4b829BEe5E03;

    // Underlying tokens on Arbitrum
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceFluid;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;

    address private proxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string("https://arbitrum-one.publicnode.com"));
        vm.createSelectFork(rpc);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        ProxyAdmin a1 = new ProxyAdmin();
        TransparentUpgradeableProxy opChecker = new TransparentUpgradeableProxy(address(checkerImpl), address(a1), initData);

        ProxyAdmin a2 = new ProxyAdmin();
        TransparentUpgradeableProxy c2pChecker = new TransparentUpgradeableProxy(address(checkerImpl), address(a2), initData);

        factory = new P2pYieldProxyFactory(p2pSigner);

        referenceFluid = address(
            new P2pErc4626Proxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceFluid);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceFluid, client, CLIENT_BPS);
    }

    // ==================== fUSDC ====================

    function test_arb_fluid_deposit_withdraw_fUSDC() external {
        _depositWithdraw(F_USDC, USDC, 10_000e6);
    }

    function test_arb_fluid_yieldAccrual_fUSDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(F_USDC, depositAmt);

        _simulateYield(F_USDC);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(F_USDC, USDC);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(F_USDC);

        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGt(treasuryDelta + clientDelta, 0, "should have distributed rewards");
        assertGt(treasuryDelta, 0, "treasury should receive fee");
    }

    function test_arb_fluid_principalProtection_fUSDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(F_USDC, depositAmt);

        _simulateYield(F_USDC);

        vm.prank(p2pOperator);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);

        uint256 remainingShares = IERC20(F_USDC).balanceOf(proxyAddress);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, remainingShares);

        uint256 clientPrincipal = IERC20(USDC).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, depositAmt - 2, "client should recover principal");
    }

    // ==================== fUSDT ====================

    function test_arb_fluid_deposit_withdraw_fUSDT() external {
        _depositWithdraw(F_USDT, USDT, 10_000e6);
    }

    function test_arb_fluid_yieldAccrual_fUSDT() external {
        uint256 depositAmt = 50_000e6;
        deal(USDT, client, depositAmt);
        _doDeposit(F_USDT, depositAmt);

        _simulateYield(F_USDT);

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(F_USDT, USDT);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDT).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(F_USDT);

        assertGt(IERC20(USDT).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ==================== Access Control ====================

    function test_arb_fluid_onlyClient_canWithdraw() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(F_USDC, 10_000e6);

        uint256 shares = IERC20(F_USDC).balanceOf(proxyAddress);

        vm.prank(p2pOperator);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, shares);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdraw(F_USDC, shares);
    }

    function test_arb_fluid_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, 100_000e6);
        _doDeposit(F_USDC, 100_000e6);

        _simulateYield(F_USDC);

        vm.prank(client);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ==================== Zero Accrued Reverts ====================

    function test_arb_fluid_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(F_USDC, 10_000e6);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pErc4626Proxy__ZeroAccruedRewards.selector);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ==================== Helpers ====================

    function _depositWithdraw(address _fToken, address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doDeposit(_fToken, _amount);

        uint256 shares = IERC20(_fToken).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold fToken shares");

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(_fToken, shares);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _doDeposit(address _fToken, uint256 _amount) private {
        address asset = IERC4626(_fToken).asset();

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceFluid, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceFluid, _fToken, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }

    function _simulateYield(address _fToken) private {
        vm.warp(block.timestamp + 365 days);
        IFToken(_fToken).updateRates();
    }
}
