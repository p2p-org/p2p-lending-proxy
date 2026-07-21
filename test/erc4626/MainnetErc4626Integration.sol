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
import "../../src/mocks/IFToken.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetErc4626Integration
/// @notice Ethereum mainnet fork tests for the generic P2pErc4626Proxy adapter.
///   Tests both Fluid fTokens and MetaMorpho vaults using the same generic proxy —
///   proving that a single adapter covers any standard ERC-4626 vault.
///
///   Fluid fTokens: fUSDC, fUSDT, fWETH (lending interest via Fluid Liquidity layer)
///   MetaMorpho vaults: Steakhouse USDC/USDT/ETH, Gauntlet USDC Core/Prime, USDT Prime, LBTC Core
///   (direct ERC-4626 deposit/withdraw, no Morpho Bundler required)
contract MainnetErc4626Integration is Test {
    using SafeERC20 for IERC20;

    // ===================== Fluid fTokens =====================
    address constant F_USDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;
    address constant F_USDT = 0x5C20B550819128074FD538Edf79791733ccEdd18;
    address constant F_WETH = 0x90551c1795392094FE6D29B758EcCD233cFAa260;

    // ===================== MetaMorpho Vaults =====================
    // Steakhouse
    address constant STEAKHOUSE_USDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
    address constant STEAKHOUSE_USDT = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;
    address constant STEAKHOUSE_ETH  = 0xBEEf050ecd6a16c4e7bfFbB52Ebba7846C4b8cD4;
    // Gauntlet
    address constant GAUNTLET_USDC_CORE  = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    address constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;
    address constant GAUNTLET_USDT_PRIME = 0x8CB3649114051cA5119141a34C200D65dc0Faa73;
    address constant GAUNTLET_LBTC_CORE  = 0xdC94785959B73F7A168452b3654E44fEc6A750e4;

    // ===================== Underlying Tokens =====================
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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

        referenceProxy = address(
            new P2pErc4626Proxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);

        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    // ========================= FLUID fUSDC =========================

    function test_erc4626_fluid_deposit_withdraw_fUSDC() external {
        _depositAndWithdraw(F_USDC, USDC, 10_000e6);
    }

    function test_erc4626_fluid_yieldAccrual_fUSDC() external {
        _yieldAccrualTest(F_USDC, USDC, 100_000e6, true);
    }

    function test_erc4626_fluid_principalProtection_fUSDC() external {
        _principalProtectionTest(F_USDC, USDC, 100_000e6, true);
    }

    // ========================= FLUID fUSDT =========================

    function test_erc4626_fluid_deposit_withdraw_fUSDT() external {
        _depositAndWithdraw(F_USDT, USDT, 10_000e6);
    }

    function test_erc4626_fluid_yieldAccrual_fUSDT() external {
        _yieldAccrualTest(F_USDT, USDT, 50_000e6, true);
    }

    // ========================= FLUID fWETH =========================

    function test_erc4626_fluid_deposit_withdraw_fWETH() external {
        _depositAndWithdraw(F_WETH, WETH, 10e18);
    }

    function test_erc4626_fluid_yieldAccrual_fWETH() external {
        _yieldAccrualTest(F_WETH, WETH, 50e18, true);
    }

    // ========================= MORPHO Steakhouse USDC =========================

    function test_erc4626_morpho_deposit_withdraw_steakhouseUSDC() external {
        _depositAndWithdraw(STEAKHOUSE_USDC, USDC, 10_000e6);
    }

    function test_erc4626_morpho_yieldAccrual_steakhouseUSDC() external {
        _yieldAccrualTest(STEAKHOUSE_USDC, USDC, 100_000e6, false);
    }

    function test_erc4626_morpho_principalProtection_steakhouseUSDC() external {
        _principalProtectionTest(STEAKHOUSE_USDC, USDC, 100_000e6, false);
    }

    // ========================= MORPHO Steakhouse USDT =========================

    function test_erc4626_morpho_deposit_withdraw_steakhouseUSDT() external {
        _depositAndWithdraw(STEAKHOUSE_USDT, USDT, 10_000e6);
    }

    function test_erc4626_morpho_yieldAccrual_steakhouseUSDT() external {
        _yieldAccrualTest(STEAKHOUSE_USDT, USDT, 50_000e6, false);
    }

    // ========================= MORPHO Steakhouse ETH =========================

    function test_erc4626_morpho_deposit_withdraw_steakhouseETH() external {
        _depositAndWithdraw(STEAKHOUSE_ETH, WETH, 10e18);
    }

    function test_erc4626_morpho_yieldAccrual_steakhouseETH() external {
        _yieldAccrualTest(STEAKHOUSE_ETH, WETH, 50e18, false);
    }

    // ========================= MORPHO Gauntlet USDC Core =========================

    function test_erc4626_morpho_deposit_withdraw_gauntletUsdcCore() external {
        _depositAndWithdraw(GAUNTLET_USDC_CORE, USDC, 10_000e6);
    }

    // ========================= MORPHO Gauntlet USDC Prime =========================

    function test_erc4626_morpho_deposit_withdraw_gauntletUsdcPrime() external {
        _depositAndWithdraw(GAUNTLET_USDC_PRIME, USDC, 10_000e6);
    }

    // ========================= MORPHO Gauntlet USDT Prime =========================

    function test_erc4626_morpho_deposit_withdraw_gauntletUsdtPrime() external {
        _depositAndWithdraw(GAUNTLET_USDT_PRIME, USDT, 10_000e6);
    }

    // ========================= MORPHO Gauntlet LBTC Core =========================

    function test_erc4626_morpho_deposit_withdraw_gauntletLbtcCore() external {
        address lbtc = IERC4626(GAUNTLET_LBTC_CORE).asset();
        _depositAndWithdraw(GAUNTLET_LBTC_CORE, lbtc, 1e8);
    }

    // ========================= Access Control =========================

    function test_erc4626_onlyClient_canWithdraw() external {
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

    function test_erc4626_onlyOperator_canWithdrawAccrued() external {
        deal(USDC, client, 100_000e6);
        _doDeposit(F_USDC, 100_000e6);

        _simulateFluidYield(F_USDC);

        vm.prank(client);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);

        vm.prank(nobody);
        vm.expectRevert();
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ========================= Zero Accrued Reverts =========================

    function test_erc4626_withdrawAccruedRewards_revertsWhenZero() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(F_USDC, 10_000e6);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pErc4626Proxy__ZeroAccruedRewards.selector);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(F_USDC);
    }

    // ========================= Multiple Deposits =========================

    function test_erc4626_multipleDeposits() external {
        uint256 first = 50_000e6;
        uint256 second = 30_000e6;
        deal(USDC, client, first + second);

        _doDeposit(STEAKHOUSE_USDC, first);
        uint256 s1 = IERC20(STEAKHOUSE_USDC).balanceOf(proxyAddress);
        assertGt(s1, 0);

        _doDeposit(STEAKHOUSE_USDC, second);
        uint256 s2 = IERC20(STEAKHOUSE_USDC).balanceOf(proxyAddress);
        assertGt(s2, s1);

        assertEq(
            P2pErc4626Proxy(proxyAddress).getTotalDeposited(USDC),
            first + second,
            "totalDeposited should sum"
        );
    }

    // ========================= supportsInterface =========================

    function test_erc4626_supportsInterface() external {
        deal(USDC, client, 10_000e6);
        _doDeposit(F_USDC, 10_000e6);

        assertTrue(
            P2pErc4626Proxy(proxyAddress).supportsInterface(type(IP2pErc4626Proxy).interfaceId),
            "should support IP2pErc4626Proxy"
        );
    }

    // ========================= Helpers =========================

    function _depositAndWithdraw(address _vault, address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doDeposit(_vault, _amount);

        uint256 shares = IERC20(_vault).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold vault shares");

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(_vault, shares);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _yieldAccrualTest(
        address _vault,
        address _asset,
        uint256 _depositAmt,
        bool _isFluid
    ) private {
        deal(_asset, client, _depositAmt);
        _doDeposit(_vault, _depositAmt);

        if (_isFluid) {
            _simulateFluidYield(_vault);
        } else {
            _simulateMorphoYield(_vault, _asset);
        }

        P2pErc4626Proxy proxy = P2pErc4626Proxy(proxyAddress);
        int256 accrued = proxy.calculateAccruedRewards(_vault, _asset);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(_asset).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(_asset).balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(_vault);

        uint256 treasuryDelta = IERC20(_asset).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(_asset).balanceOf(client) - clientBefore;
        assertGt(treasuryDelta + clientDelta, 0, "should have distributed rewards");
        assertGt(treasuryDelta, 0, "treasury should receive fee");
    }

    function _principalProtectionTest(
        address _vault,
        address _asset,
        uint256 _depositAmt,
        bool _isFluid
    ) private {
        deal(_asset, client, _depositAmt);
        _doDeposit(_vault, _depositAmt);

        if (_isFluid) {
            _simulateFluidYield(_vault);
        } else {
            _simulateMorphoYield(_vault, _asset);
        }

        vm.prank(p2pOperator);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(_vault);

        uint256 remainingShares = IERC20(_vault).balanceOf(proxyAddress);
        uint256 clientBefore = IERC20(_asset).balanceOf(client);

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(_vault, remainingShares);

        uint256 clientPrincipal = IERC20(_asset).balanceOf(client) - clientBefore;
        assertGe(clientPrincipal, _depositAmt - 2, "client should recover principal");
    }

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

    /// @dev For Fluid: warp time + call updateRates() to refresh exchange price.
    function _simulateFluidYield(address _vault) private {
        vm.warp(block.timestamp + 365 days);
        IFToken(_vault).updateRates();
    }

    /// @dev For MetaMorpho: warp time so Morpho Blue market interest accrues.
    /// MetaMorpho's totalAssets() calls expectedSupplyAssets() on each market,
    /// which computes accrued interest based on block.timestamp.
    function _simulateMorphoYield(address, address) private {
        vm.warp(block.timestamp + 365 days);
    }
}
