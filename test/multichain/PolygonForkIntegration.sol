// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

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
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title PolygonForkIntegration
/// @notice Polygon fork tests for P2pAaveProxy and P2pCompoundProxy.
///   Verifies deposit/withdraw for USDT, DAI, USDC on Aave V3 and USDT on Compound V3.
contract PolygonForkIntegration is Test {
    using SafeERC20 for IERC20;

    // --- Polygon Aave V3 ---
    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_DATA_PROVIDER = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

    // --- Polygon Compound V3 ---
    address constant USDT_COMET = 0xaeB318360f27748Acb200CE616E389A6C9409a07;
    address constant COMET_REWARDS = 0x45939657d1CA34A8FA39A924B71D28Fe8431e581;

    // --- Polygon Tokens ---
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // USDC.e (bridged)
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant DAI  = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceAave;
    address private referenceCompound;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;

    address private aaveProxyAddress;
    address private compoundProxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("POLYGON_RPC_URL", string("https://polygon-bor.publicnode.com"));
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

        // Aave V3 reference
        referenceAave = address(
            new P2pAaveProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                AAVE_POOL, AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceAave);

        // Compound V3 reference (USDT market only on Polygon)
        address[] memory assets = new address[](1);
        address[] memory comets = new address[](1);
        assets[0] = USDT; comets[0] = USDT_COMET;
        CompoundMarketRegistry registry = new CompoundMarketRegistry(address(factory), assets, comets);

        referenceCompound = address(
            new P2pCompoundProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                address(registry), COMET_REWARDS
            )
        );
        factory.addReferenceP2pYieldProxy(referenceCompound);

        vm.stopPrank();

        aaveProxyAddress = factory.predictP2pYieldProxyAddress(referenceAave, client, CLIENT_BPS);
        compoundProxyAddress = factory.predictP2pYieldProxyAddress(referenceCompound, client, CLIENT_BPS);
    }

    // ===================== Aave V3 =====================

    function test_polygon_aave_deposit_withdraw_USDC() external {
        _aaveDepositWithdraw(USDC, 10_000e6);
    }

    function test_polygon_aave_deposit_withdraw_USDT() external {
        _aaveDepositWithdraw(USDT, 10_000e6);
    }

    function test_polygon_aave_deposit_withdraw_DAI() external {
        _aaveDepositWithdraw(DAI, 10_000e18);
    }

    function test_polygon_aave_yieldAccrual_USDC() external {
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

    function test_polygon_compound_deposit_withdraw_USDT() external {
        _compoundDepositWithdraw(USDT, 10_000e6);
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
