// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/aave/p2pAaveProxy/P2pAaveProxy.sol";
import "../../src/adapters/aave/@aave/IAaveV3Pool.sol";
import "../../src/adapters/compound/p2pCompoundProxy/P2pCompoundProxy.sol";
import "../../src/adapters/compound/CompoundMarketRegistry.sol";
import "../../src/adapters/compound/@compound/IComet.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title BaseForkIntegration
/// @notice Base fork tests for P2pAaveProxy, P2pCompoundProxy, and P2pErc4626Proxy.
///   Verifies deposit/withdraw for assets Kiln DeFi uses on Base.
contract BaseForkIntegration is Test {
    using SafeERC20 for IERC20;

    // --- Base Aave V3 ---
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant AAVE_DATA_PROVIDER = 0x2d8A3C5677189723C4cB8873CfC9C8976FDF38Ac;

    // --- Base Compound V3 ---
    address constant USDC_COMET = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
    address constant COMET_REWARDS = 0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1;

    // --- Base MetaMorpho (via generic ERC-4626) ---
    // MetaMorpho vaults on Base
    address constant STEAKHOUSE_USDC = 0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183;
    address constant MOONWELL_USDC   = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

    // --- Base Tokens ---
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceAave;
    address private referenceCompound;
    address private referenceMorpho;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;

    address private aaveProxyAddress;
    address private compoundProxyAddress;
    address private morphoProxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string("https://base.publicnode.com"));
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

        // Aave V3
        referenceAave = address(
            new P2pAaveProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                AAVE_POOL, AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceAave);

        // Compound V3 (USDC only on Base)
        address[] memory assets = new address[](1);
        address[] memory comets = new address[](1);
        assets[0] = USDC; comets[0] = USDC_COMET;
        CompoundMarketRegistry registry = new CompoundMarketRegistry(address(factory), assets, comets);

        referenceCompound = address(
            new P2pCompoundProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                address(registry), COMET_REWARDS
            )
        );
        factory.addReferenceP2pYieldProxy(referenceCompound);

        // Morpho (MetaMorpho vaults via generic ERC-4626)
        referenceMorpho = address(
            new P2pErc4626Proxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceMorpho);

        vm.stopPrank();

        aaveProxyAddress = factory.predictP2pYieldProxyAddress(referenceAave, client, CLIENT_BPS);
        compoundProxyAddress = factory.predictP2pYieldProxyAddress(referenceCompound, client, CLIENT_BPS);
        morphoProxyAddress = factory.predictP2pYieldProxyAddress(referenceMorpho, client, CLIENT_BPS);
    }

    // ===================== Aave V3 =====================

    function test_base_aave_deposit_withdraw_USDC() external {
        _aaveDepositWithdraw(USDC, 10_000e6);
    }

    function test_base_aave_yieldAccrual_USDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doAaveDeposit(USDC, depositAmt);

        uint256 yieldAmt = 5_000e6;
        address donor = makeAddr("donor");
        deal(USDC, donor, yieldAmt);
        vm.startPrank(donor);
        IERC20(USDC).safeApprove(AAVE_POOL, yieldAmt);
        IAaveV3Pool(AAVE_POOL).supply(USDC, yieldAmt, aaveProxyAddress, 0);
        vm.stopPrank();

        P2pAaveProxy proxy = P2pAaveProxy(aaveProxyAddress);
        address aToken = proxy.getAToken(USDC);
        int256 accrued = proxy.calculateAccruedRewards(aToken, USDC);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(USDC);
        assertGt(IERC20(USDC).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ===================== Compound V3 =====================

    function test_base_compound_deposit_withdraw_USDC() external {
        _compoundDepositWithdraw(USDC, 10_000e6);
    }

    // ===================== Morpho (MetaMorpho) =====================

    function test_base_morpho_deposit_withdraw_steakhouseUSDC() external {
        _morphoDepositWithdraw(STEAKHOUSE_USDC, USDC, 10_000e6);
    }

    function test_base_morpho_deposit_withdraw_moonwellUSDC() external {
        _morphoDepositWithdraw(MOONWELL_USDC, USDC, 10_000e6);
    }

    // ===================== Helpers =====================

    function _aaveDepositWithdraw(address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doAaveDeposit(_asset, _amount);

        address aToken = P2pAaveProxy(aaveProxyAddress).getAToken(_asset);
        assertGt(IERC20(aToken).balanceOf(aaveProxyAddress), 0, "should hold aToken");

        vm.prank(client);
        P2pAaveProxy(aaveProxyAddress).withdraw(_asset, type(uint256).max);
        assertEq(IERC20(aToken).balanceOf(aaveProxyAddress), 0, "aToken balance should be 0");
    }

    function _compoundDepositWithdraw(address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doCompoundDeposit(_asset, _amount);

        P2pCompoundProxy proxy = P2pCompoundProxy(compoundProxyAddress);
        assertGt(proxy.getTotalDeposited(_asset), 0, "totalDeposited should be > 0");

        vm.prank(client);
        proxy.withdraw(_asset, type(uint256).max);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _morphoDepositWithdraw(address _vault, address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceMorpho, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(_asset).safeApprove(morphoProxyAddress, 0);
        IERC20(_asset).safeApprove(morphoProxyAddress, type(uint256).max);
        factory.deposit(referenceMorpho, _vault, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();

        uint256 shares = IERC20(_vault).balanceOf(morphoProxyAddress);
        assertGt(shares, 0, "should hold vault shares");

        vm.prank(client);
        P2pErc4626Proxy(morphoProxyAddress).withdraw(_vault, shares);

        uint256 clientBal = IERC20(_asset).balanceOf(client);
        assertGe(clientBal, _amount - 2, "client should recover funds");
    }

    function _doAaveDeposit(address _asset, uint256 _amount) private {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceAave, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(_asset).safeApprove(aaveProxyAddress, 0);
        IERC20(_asset).safeApprove(aaveProxyAddress, type(uint256).max);
        factory.deposit(referenceAave, _asset, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }

    function _doCompoundDeposit(address _asset, uint256 _amount) private {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceCompound, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));

        vm.startPrank(client);
        IERC20(_asset).safeApprove(compoundProxyAddress, 0);
        IERC20(_asset).safeApprove(compoundProxyAddress, type(uint256).max);
        factory.deposit(referenceCompound, _asset, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }
}
