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
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title OptimismForkIntegration
/// @notice Optimism fork tests for P2pAaveProxy.
///   Verifies deposit/withdraw for DAI, USDT, USDC — assets Kiln DeFi uses on Optimism.
contract OptimismForkIntegration is Test {
    using SafeERC20 for IERC20;

    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_DATA_PROVIDER = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant USDT = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address constant DAI  = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    uint96 constant CLIENT_BPS = 9_000;

    P2pYieldProxyFactory private factory;
    address private referenceAave;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private proxyAddress;

    function setUp() public {
        string memory rpc = vm.envOr("OPTIMISM_RPC_URL", string("https://optimism.publicnode.com"));
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

        referenceAave = address(
            new P2pAaveProxy(
                address(factory), P2P_TREASURY,
                address(opChecker), address(c2pChecker),
                AAVE_POOL, AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceAave);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceAave, client, CLIENT_BPS);
    }

    function test_op_aave_deposit_withdraw_USDC() external {
        _depositWithdraw(USDC, 10_000e6);
    }

    function test_op_aave_deposit_withdraw_USDT() external {
        _depositWithdraw(USDT, 10_000e6);
    }

    function test_op_aave_deposit_withdraw_DAI() external {
        _depositWithdraw(DAI, 10_000e18);
    }

    function test_op_aave_yieldAccrual_USDC() external {
        uint256 depositAmt = 100_000e6;
        deal(USDC, client, depositAmt);
        _doDeposit(USDC, depositAmt);

        uint256 yieldAmt = 5_000e6;
        address donor = makeAddr("donor");
        deal(USDC, donor, yieldAmt);
        vm.startPrank(donor);
        IERC20(USDC).safeApprove(AAVE_POOL, yieldAmt);
        IAaveV3Pool(AAVE_POOL).supply(USDC, yieldAmt, proxyAddress, 0);
        vm.stopPrank();

        P2pAaveProxy proxy = P2pAaveProxy(proxyAddress);
        address aToken = proxy.getAToken(USDC);
        int256 accrued = proxy.calculateAccruedRewards(aToken, USDC);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(USDC);
        assertGt(IERC20(USDC).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

    // ===================== Helpers =====================

    function _depositWithdraw(address _asset, uint256 _amount) private {
        deal(_asset, client, _amount);
        _doDeposit(_asset, _amount);

        address aToken = P2pAaveProxy(proxyAddress).getAToken(_asset);
        assertGt(IERC20(aToken).balanceOf(proxyAddress), 0, "should hold aToken");

        vm.prank(client);
        P2pAaveProxy(proxyAddress).withdraw(_asset, type(uint256).max);
        assertEq(IERC20(aToken).balanceOf(proxyAddress), 0, "aToken balance should be 0");
    }

    function _doDeposit(address _asset, uint256 _amount) private {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 hash = factory.getHashForP2pSigner(referenceAave, client, CLIENT_BPS, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ECDSA.toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceAave, _asset, _amount, CLIENT_BPS, deadline, sig);
        vm.stopPrank();
    }
}
