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

/// @title ArbitrumForkIntegration
/// @notice Arbitrum fork tests for P2pAaveProxy and P2pCompoundProxy.
///   Verifies deposit/withdraw for all assets Kiln DeFi uses on Arbitrum.
contract ArbitrumForkIntegration is Test {
    using SafeERC20 for IERC20;

    // --- Arbitrum Aave V3 ---
    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_DATA_PROVIDER = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

    // --- Arbitrum Compound V3 ---
    address constant USDC_COMET  = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address constant USDT_COMET  = 0xd98Be00b5D27fc98112BdE293e487f8D4cA57d07;
    address constant USDCE_COMET = 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA;
    address constant COMET_REWARDS = 0x88730d254A2F7e6ac7591E0dE2a3e9E28db4c2e5;

    // --- Arbitrum Tokens ---
    address constant USDC  = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT  = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI   = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant WETH  = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDCE = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

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
        string memory rpc = vm.envOr("ARBITRUM_RPC_URL", string("https://arbitrum-one.publicnode.com"));
        vm.createSelectFork(rpc);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        ProxyAdmin opAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy opChecker = new TransparentUpgradeableProxy(address(checkerImpl), address(opAdmin), initData);

        ProxyAdmin c2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy c2pChecker = new TransparentUpgradeableProxy(address(checkerImpl), address(c2pAdmin), initData);

        factory = new P2pYieldProxyFactory(p2pSigner);

        // Aave reference
        referenceAave = address(
            new P2pAaveProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                AAVE_POOL, AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceAave);

        // Compound reference
        address[] memory assets = new address[](3);
        address[] memory comets = new address[](3);
        assets[0] = USDC;  comets[0] = USDC_COMET;
        assets[1] = USDT;  comets[1] = USDT_COMET;
        assets[2] = USDCE; comets[2] = USDCE_COMET;
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

    function test_arb_aave_deposit_withdraw_USDC() external {
        _aaveDepositWithdraw(USDC, 10_000e6);
    }

    function test_arb_aave_deposit_withdraw_USDT() external {
        _aaveDepositWithdraw(USDT, 10_000e6);
    }

    function test_arb_aave_deposit_withdraw_DAI() external {
        _aaveDepositWithdraw(DAI, 10_000e18);
    }

    function test_arb_aave_deposit_withdraw_WETH() external {
        _aaveDepositWithdraw(WETH, 10e18);
    }

    function test_arb_aave_yieldAccrual_USDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doAaveDeposit(USDC, depositAmt);

        // Simulate yield
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
        uint256 treasuryAfter = IERC20(USDC).balanceOf(P2P_TREASURY);
        assertGt(treasuryAfter, treasuryBefore, "treasury should receive fee");
    }

    // ===================== Compound V3 =====================

    function test_arb_compound_deposit_withdraw_USDC() external {
        _compoundDepositWithdraw(USDC, 10_000e6);
    }

    function test_arb_compound_deposit_withdraw_USDT() external {
        _compoundDepositWithdraw(USDT, 10_000e6);
    }

    function test_arb_compound_deposit_withdraw_USDCe() external {
        _compoundDepositWithdraw(USDCE, 10_000e6);
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

        // Verify comet balance > 0
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
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.startPrank(client);
        IERC20(_asset).safeApprove(aaveProxyAddress, 0);
        IERC20(_asset).safeApprove(aaveProxyAddress, type(uint256).max);
        factory.deposit(referenceAave, _asset, _amount, CLIENT_BPS, deadline, sig);
        vm.stopPrank();
    }

    function _doCompoundDeposit(address _asset, uint256 _amount) private {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceCompound, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.startPrank(client);
        IERC20(_asset).safeApprove(compoundProxyAddress, 0);
        IERC20(_asset).safeApprove(compoundProxyAddress, type(uint256).max);
        factory.deposit(referenceCompound, _asset, _amount, CLIENT_BPS, deadline, sig);
        vm.stopPrank();
    }
}
