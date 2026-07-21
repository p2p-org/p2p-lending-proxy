// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/access/P2pOperator.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/p2pYieldProxy/P2pYieldProxy.sol";
import "../../src/p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "forge-std/Test.sol";

contract MainnetIntegration is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant VAULT_USDC = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant VAULT_USDT = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;

    uint256 constant SIG_DEADLINE = 1_734_464_723;
    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000;

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private clientKey;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private nobody;
    address private allowedChecker;
    address private referenceProxy;

    address private proxyAddress;
    address private asset;
    address private vault;

    function setUp() public {
        vm.createSelectFork("mainnet", 21_308_893);

        (client, clientKey) = makeAddrAndKey("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperator);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy checkerProxy =
            new TransparentUpgradeableProxy(address(implementation), address(admin), initData);
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pCheckerProxy =
            new TransparentUpgradeableProxy(address(clientToP2pImpl), address(clientToP2pAdmin), initData);
        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pErc4626Proxy(
                address(factory),
                P2P_TREASURY,
                address(checkerProxy),
                address(clientToP2pCheckerProxy)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        allowedChecker = address(checkerProxy);

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
        asset = USDC;
        vault = VAULT_USDC;
    }

    function test_morpho_HappyPath_USDC_Mainnet() external {
        asset = USDC;
        vault = VAULT_USDC;
        _happyPath();
    }

    function test_morpho_HappyPath_USDT_Mainnet() external {
        asset = USDT;
        vault = VAULT_USDT;
        _happyPath();
    }

    function test_morpho_profitSplit_Mainnet() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, 100e6);

        uint256 clientBalanceBefore = IERC20(asset).balanceOf(client);
        uint256 treasuryBalanceBefore = IERC20(asset).balanceOf(P2P_TREASURY);

        _doDeposit();

        uint256 shares = IERC20(vault).balanceOf(proxyAddress);
        uint256 assetsBefore = IERC4626(vault).convertToAssets(shares);

        _forward(1_000_000);

        uint256 assetsAfter = IERC4626(vault).convertToAssets(shares);
        uint256 profit = assetsAfter - assetsBefore;

        _doWithdraw(1);

        uint256 clientBalanceAfter = IERC20(asset).balanceOf(client);
        uint256 treasuryBalanceAfter = IERC20(asset).balanceOf(P2P_TREASURY);

        uint256 clientChange = clientBalanceAfter - clientBalanceBefore;
        uint256 treasuryChange = treasuryBalanceAfter - treasuryBalanceBefore;
        uint256 totalChange = clientChange + treasuryChange;

        assertApproxEqAbs(totalChange, profit, 1);
        uint256 clientShare = clientChange * 10_000 / totalChange;
        uint256 treasuryShare = treasuryChange * 10_000 / totalChange;

        assertApproxEqAbs(CLIENT_BPS, clientShare, 1);
        assertApproxEqAbs(10_000 - CLIENT_BPS, treasuryShare, 1);
    }

    function test_morpho_withdrawAccruedRewards_byOperator() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, 100e6);

        _doDeposit();
        _forward(1_000_000);

        vm.startPrank(p2pOperator);
        uint256 treasuryBefore = IERC20(asset).balanceOf(P2P_TREASURY);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(vault);
        uint256 treasuryAfter = IERC20(asset).balanceOf(P2P_TREASURY);
        vm.stopPrank();

        assertGt(treasuryAfter, treasuryBefore);
    }

    function test_morpho_withdrawAccruedRewards_revertsForClient() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, 100e6);
        _doDeposit();

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pErc4626Proxy__NotP2pOperator.selector, client));
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(vault);
        vm.stopPrank();
    }

    function test_morpho_transferP2pSigner() external {
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        vm.startPrank(p2pOperator);
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        assertEq(factory.getP2pSigner(), nobody);
    }


    function test_morpho_clientBasisPointsGreaterThan10000() external {
        uint96 invalidBasisPoints = 10_001;
        bytes memory signature = _getP2pSignerSignature(invalidBasisPoints, SIG_DEADLINE);

        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__InvalidClientBasisPoints.selector, invalidBasisPoints));
        factory.deposit(
            referenceProxy,
            vault, DEPOSIT_AMOUNT, invalidBasisPoints, SIG_DEADLINE, signature);
        vm.stopPrank();
    }

    function test_morpho_zeroAddressVault() external {
        asset = USDC;
        bytes memory signature = _getP2pSignerSignature(CLIENT_BPS, SIG_DEADLINE);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pErc4626Proxy__ZeroVaultAddress.selector));
        factory.deposit(
            referenceProxy,
            address(0), DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signature);
        vm.stopPrank();
    }

    function test_morpho_zeroAssetAmount() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        (bool success, bytes memory returndata) = address(factory).call(
            abi.encodeWithSelector(
                bytes4(keccak256("deposit(address,address,uint256,uint96,uint256,bytes)")),
                referenceProxy,
                vault,
                0,
                CLIENT_BPS,
                SIG_DEADLINE,
                _getP2pSignerSignature(CLIENT_BPS, SIG_DEADLINE)
            )
        );
        vm.stopPrank();

        assertFalse(success);
        assertEq(bytes4(returndata), P2pYieldProxy__ZeroAssetAmount.selector);
    }

    function test_morpho_depositDirectlyOnProxy_reverts() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, DEPOSIT_AMOUNT);
        _doDeposit();

        vm.startPrank(client);
        vm.expectRevert(
            abi.encodeWithSelector(P2pYieldProxy__NotFactoryCalled.selector, client, factory)
        );
        P2pErc4626Proxy(proxyAddress).deposit(vault, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_morpho_initializeDirectlyOnProxy_reverts() external {
        deal(asset, client, DEPOSIT_AMOUNT);
        _doDeposit();

        vm.expectRevert("Initializable: contract is already initialized");
        P2pErc4626Proxy(proxyAddress).initialize(client, CLIENT_BPS);
    }

    function test_morpho_withdrawOnProxyOnlyCallableByClient() external {
        deal(asset, client, DEPOSIT_AMOUNT);
        _doDeposit();

        uint256 shares = IERC20(vault).balanceOf(proxyAddress);

        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, nobody, client)
        );
        P2pErc4626Proxy(proxyAddress).withdraw(vault, shares);
        vm.stopPrank();
    }

    function test_morpho_callAnyFunction_revertsByDefault() external {
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        AllowedCalldataChecker(allowedChecker).checkCalldata(
            address(0),
            bytes4(0xdeadbeef),
            bytes("")
        );
    }

    function test_morpho_getHashForP2pSigner() external view {
                bytes32 expected = keccak256(
            abi.encode(referenceProxy, client, CLIENT_BPS, SIG_DEADLINE, address(factory), block.chainid)
        );
        assertEq(factory.getHashForP2pSigner(
            referenceProxy,
            client, CLIENT_BPS, SIG_DEADLINE), expected);
    }

    function test_morpho_supportsInterface() external view {
        assertTrue(factory.supportsInterface(type(IP2pYieldProxyFactory).interfaceId));
        assertFalse(factory.supportsInterface(type(IERC4626).interfaceId));
    }

    function test_morpho_p2pSignerSignatureExpired() external {
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory signature = _getP2pSignerSignature(CLIENT_BPS, expiredDeadline);

        deal(asset, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(P2pYieldProxyFactory__P2pSignerSignatureExpired.selector, expiredDeadline)
        );
        factory.deposit(
            referenceProxy,
            vault, DEPOSIT_AMOUNT, CLIENT_BPS, expiredDeadline, signature);
        vm.stopPrank();
    }

    function test_morpho_invalidP2pSignerSignature() external {
        bytes memory signature = _getP2pSignerSignature(CLIENT_BPS + 1, SIG_DEADLINE);

        deal(asset, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);
        factory.deposit(
            referenceProxy,
            vault, DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signature);
        vm.stopPrank();
    }

    function test_morpho_viewFunctions() external view {
        assertTrue(referenceProxy != address(0));
        assertEq(factory.getP2pSigner(), p2pSigner);
        assertEq(factory.getP2pOperator(), p2pOperator);
        assertEq(factory.getAllProxies().length, 0);
    }

    function test_morpho_acceptP2pOperator() external {
        assertEq(factory.getP2pOperator(), p2pOperator);

        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pOperator(nobody);
        vm.stopPrank();

        address newOperator = makeAddr("newOperator");
        vm.startPrank(p2pOperator);
        factory.transferP2pOperator(newOperator);
        vm.stopPrank();
        assertEq(factory.getPendingP2pOperator(), newOperator);

        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.acceptP2pOperator();
        vm.stopPrank();

        vm.startPrank(newOperator);
        factory.acceptP2pOperator();
        vm.stopPrank();

        assertEq(factory.getP2pOperator(), newOperator);
        assertEq(factory.getPendingP2pOperator(), address(0));
    }

    function test_morpho_multipleDepositsReuseProxy() external {
        asset = USDC;
        vault = VAULT_USDC;
        deal(asset, client, DEPOSIT_AMOUNT * 2);

        _doDeposit();
        uint256 proxiesCountAfterFirstDeposit = factory.getAllProxies().length;
        assertEq(proxiesCountAfterFirstDeposit, 1);

        _doDeposit();
        uint256 proxiesCountAfterSecondDeposit = factory.getAllProxies().length;
        assertEq(proxiesCountAfterSecondDeposit, 1);
        assertEq(factory.getAllProxies()[0], proxyAddress);
    }

    function _happyPath() private {
        deal(asset, client, DEPOSIT_AMOUNT * 6);

        uint256 assetBefore = IERC20(asset).balanceOf(client);
        assertEq(IERC20(vault).balanceOf(proxyAddress), 0);

        _doDeposit();
        uint256 assetAfterDeposit1 = IERC20(asset).balanceOf(client);
        uint256 sharesAfterDeposit1 = IERC20(vault).balanceOf(proxyAddress);
        assertGt(sharesAfterDeposit1, 0);
        assertEq(assetBefore - assetAfterDeposit1, DEPOSIT_AMOUNT);

        _doDeposit();
        uint256 assetAfterDeposit2 = IERC20(asset).balanceOf(client);
        uint256 sharesAfterDeposit2 = IERC20(vault).balanceOf(proxyAddress);
        assertEq(assetAfterDeposit1 - assetAfterDeposit2, DEPOSIT_AMOUNT);
        assertEq(sharesAfterDeposit2 - sharesAfterDeposit1, sharesAfterDeposit1);

        _doDeposit();
        _doDeposit();

        uint256 assetAfterAllDeposits = IERC20(asset).balanceOf(client);

        _doWithdraw(10);
        uint256 assetAfterWithdraw1 = IERC20(asset).balanceOf(client);
        assertApproxEqAbs(assetAfterWithdraw1 - assetAfterAllDeposits, DEPOSIT_AMOUNT * 4 / 10, 1);

        _doWithdraw(5);
        _doWithdraw(3);
        _doWithdraw(2);
        _doWithdraw(1);

        assertApproxEqAbs(IERC20(asset).balanceOf(client), assetBefore, 1);
        assertEq(IERC20(vault).balanceOf(proxyAddress), 0);
    }

    function _doDeposit() private {
        bytes memory signature = _getP2pSignerSignature(CLIENT_BPS, SIG_DEADLINE);

        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(
            referenceProxy,
            vault, DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signature);
        vm.stopPrank();
    }

    function _doWithdraw(uint256 denominator) private {
        uint256 sharesBalance = IERC20(vault).balanceOf(proxyAddress);
        uint256 sharesToWithdraw = sharesBalance / denominator;

        vm.startPrank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(vault, sharesToWithdraw);
        vm.stopPrank();
    }

    function _getP2pSignerSignature(uint96 clientBasisPoints, uint256 deadline)
        private
        view
        returns (bytes memory)
    {
        bytes32 hashForSigner = factory.getHashForP2pSigner(
            referenceProxy,
            client, clientBasisPoints, deadline);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _forward(uint256 blocks) private {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks);
    }

    /// BUG-FLOW TEST
function test_morpho_DoubleFeeCollectionBug_OperatorThenClientWithdraw() external {
    // ============================================================
    // STEP 1: CLIENT DEPOSITS 1000 USDC
    // BUG-FLOW: s_totalDeposited = 1000, s_totalWithdrawn = 0
    // ============================================================
    asset = USDC;
    vault = VAULT_USDC;
    uint256 depositAmount = 1000e6; // 1000 USDC
    deal(asset, client, depositAmount);

    bytes memory signature = _getP2pSignerSignature(CLIENT_BPS, SIG_DEADLINE);
    vm.startPrank(client);
    IERC20(asset).safeApprove(proxyAddress, 0);
    IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
    factory.deposit(
            referenceProxy,
            vault, depositAmount, CLIENT_BPS, SIG_DEADLINE, signature);
    vm.stopPrank();

    uint256 clientStart = IERC20(asset).balanceOf(client);
    uint256 treasuryStart = IERC20(asset).balanceOf(P2P_TREASURY);

    // ============================================================
    // STEP 2: VAULT ACCRUES 5.96 USDC PROFIT
    // BUG-FLOW: Vault grows from 1000 to 1005.96 USDC
    // getUserPrincipal() = 1000 - 0 = 1000
    // calculateAccruedRewards() = 1005.96 - 1000 = 5.96
    // ============================================================
    uint256 shares = IERC20(vault).balanceOf(proxyAddress);
    uint256 assetsBefore = IERC4626(vault).convertToAssets(shares);
    _forward(1_000_000);
    uint256 assetsAfter = IERC4626(vault).convertToAssets(shares);
    uint256 profit = assetsAfter - assetsBefore;

    // ============================================================
    // STEP 3: OPERATOR WITHDRAWS PROFIT
    // ============================================================
    vm.prank(p2pOperator);
    P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(vault);

    // ============================================================
    // STEP 4: CLIENT WITHDRAWS REMAINING (PRINCIPAL)
    // ============================================================
    uint256 remainingShares = IERC20(vault).balanceOf(proxyAddress);
    vm.prank(client);
    P2pErc4626Proxy(proxyAddress).withdraw(vault, remainingShares);

    // Calculate results
    uint256 clientReceived = IERC20(asset).balanceOf(client) - clientStart;
    uint256 treasuryReceived = IERC20(asset).balanceOf(P2P_TREASURY) - treasuryStart;
    uint256 expectedClient = depositAmount + ((profit * CLIENT_BPS) / 10_000);
    uint256 expectedTreasury = (profit * (10_000 - CLIENT_BPS)) / 10_000;
    uint256 clientLoss = expectedClient - clientReceived;
    uint256 treasuryExtra = treasuryReceived - expectedTreasury;

    console.log("\n=== BUG: Double Fee Collection (1000 USDC Deposit) ===");
    console.log("Deposit:  1000.00 USDC");
    console.log("Profit:   %s.%s USDC", profit / 1e6, (profit % 1e6) / 1e4);
    console.log("\nClient:");
    console.log("  Expected: %s.%s USDC", expectedClient / 1e6, (expectedClient % 1e6) / 1e4);
    console.log("  Actual:   %s.%s USDC", clientReceived / 1e6, (clientReceived % 1e6) / 1e4);
    console.log("  LOST:     %s.%s USDC", clientLoss / 1e6, (clientLoss % 1e6) / 1e4);
    console.log("\nTreasury:");
    console.log("  Expected: %s.%s USDC", expectedTreasury / 1e6, (expectedTreasury % 1e6) / 1e4);
    console.log("  Actual:   %s.%s USDC", treasuryReceived / 1e6, (treasuryReceived % 1e6) / 1e4);
    console.log("  EXTRA:    %s.%s USDC (collected ~2x fees!)", treasuryExtra / 1e6, (treasuryExtra % 1e6) / 1e4);

    uint256 clientDelta = clientReceived > expectedClient
        ? clientReceived - expectedClient
        : expectedClient - clientReceived;
    assertLe(clientDelta, 2, "Client lost funds");

    uint256 treasuryDelta = treasuryReceived > expectedTreasury
        ? treasuryReceived - expectedTreasury
        : expectedTreasury - treasuryReceived;
    assertLe(treasuryDelta, 2, "Treasury gained extra");
}
}
