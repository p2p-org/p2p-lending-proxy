// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title EthereumMorphoVaultsFork
/// @notice Ethereum mainnet fork tests for P2pErc4626Proxy across all MetaMorpho vault
///   variants that Kiln DeFi uses: Steakhouse, Gauntlet, Re7.
contract EthereumMorphoVaultsFork is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;

    // --- Tokens ---
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // --- MetaMorpho Vaults (Ethereum) ---
    // Steakhouse
    address constant STEAKHOUSE_USDC = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;
    address constant STEAKHOUSE_USDT = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;
    address constant STEAKHOUSE_ETH  = 0xBEEf050ecd6a16c4e7bfFbB52Ebba7846C4b8cD4;
    // Gauntlet
    address constant GAUNTLET_USDC_CORE  = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    address constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;
    address constant GAUNTLET_USDT_PRIME = 0x8CB3649114051cA5119141a34C200D65dc0Faa73;
    address constant GAUNTLET_LBTC_CORE  = 0xdC94785959B73F7A168452b3654E44fEc6A750e4;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant USDC_DEPOSIT = 10_000e6;
    uint256 constant USDT_DEPOSIT = 10_000e6;
    uint256 constant WETH_DEPOSIT = 5e18;

    P2pYieldProxyFactory private factory;
    address private referenceProxy;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private proxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(rpc);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker impl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        ProxyAdmin a1 = new ProxyAdmin();
        TransparentUpgradeableProxy opChecker = new TransparentUpgradeableProxy(address(impl), address(a1), initData);
        ProxyAdmin a2 = new ProxyAdmin();
        TransparentUpgradeableProxy c2pChecker = new TransparentUpgradeableProxy(address(impl), address(a2), initData);

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

    // ===================== Steakhouse Vaults =====================

    function test_eth_morpho_steakhouseUSDC() external {
        _depositWithdraw(STEAKHOUSE_USDC, USDC, USDC_DEPOSIT);
    }

    function test_eth_morpho_steakhouseUSDT() external {
        _depositWithdraw(STEAKHOUSE_USDT, USDT, USDT_DEPOSIT);
    }

    function test_eth_morpho_steakhouseETH() external {
        _depositWithdraw(STEAKHOUSE_ETH, WETH, WETH_DEPOSIT);
    }

    // ===================== Gauntlet Vaults =====================

    function test_eth_morpho_gauntletUSDC_Core() external {
        _depositWithdraw(GAUNTLET_USDC_CORE, USDC, USDC_DEPOSIT);
    }

    function test_eth_morpho_gauntletUSDC_Prime() external {
        _depositWithdraw(GAUNTLET_USDC_PRIME, USDC, USDC_DEPOSIT);
    }

    function test_eth_morpho_gauntletUSDT_Prime() external {
        _depositWithdraw(GAUNTLET_USDT_PRIME, USDT, USDT_DEPOSIT);
    }

    function test_eth_morpho_gauntletLBTC_Core() external {
        // LBTC underlying — get asset from vault
        address lbtc = IERC4626(GAUNTLET_LBTC_CORE).asset();
        uint256 depositAmt = 1e8; // LBTC has 8 decimals
        deal(lbtc, client, depositAmt);
        _doDeposit(GAUNTLET_LBTC_CORE, lbtc, depositAmt);

        uint256 shares = IERC20(GAUNTLET_LBTC_CORE).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold vault shares");

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(GAUNTLET_LBTC_CORE, shares);

        uint256 clientBal = IERC20(lbtc).balanceOf(client);
        assertGe(clientBal, depositAmt - 2, "client should recover LBTC");
    }

    // ===================== Yield Accrual =====================

    function test_eth_morpho_yieldAccrual_steakhouseUSDC() external {
        deal(USDC, client, USDC_DEPOSIT);
        _doDeposit(STEAKHOUSE_USDC, USDC, USDC_DEPOSIT);

        // Warp to accrue yield (Morpho Blue interest accrues based on timestamp)
        vm.warp(block.timestamp + 365 days);

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        vm.prank(p2pOperator);
        P2pErc4626Proxy(proxyAddress).withdrawAccruedRewards(STEAKHOUSE_USDC);

        assertGt(IERC20(USDC).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ===================== Helpers =====================

    function _depositWithdraw(address _vault, address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doDeposit(_vault, _asset, _amount);

        uint256 shares = IERC20(_vault).balanceOf(proxyAddress);
        assertGt(shares, 0, "should hold vault shares");

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(_vault, shares);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _doDeposit(address _vault, address _asset, uint256 _amount) private {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, _vault, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }
}
