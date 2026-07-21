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

/// @title BnbForkIntegration
/// @notice BNB Chain fork tests for P2pAaveProxy.
///   Verifies deposit/withdraw for USDT and USDC — assets Kiln DeFi uses on BNB.
contract BnbForkIntegration is Test {
    using SafeERC20 for IERC20;

    address constant AAVE_POOL = 0x6807dc923806fE8Fd134338EABCA509979a7e0cB;
    address constant AAVE_DATA_PROVIDER = 0x41585C50524fb8c3899B43D7D797d9486AAc94DB;

    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

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
        string memory rpc = vm.envOr("BNB_RPC_URL", string("https://bsc.publicnode.com"));
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

    function test_bnb_aave_deposit_withdraw_USDT() external {
        _depositWithdraw(USDT, 10_000e18); // BSC USDT is 18 decimals
    }

    function test_bnb_aave_deposit_withdraw_USDC() external {
        _depositWithdraw(USDC, 10_000e18); // BSC USDC is 18 decimals
    }

    function test_bnb_aave_yieldAccrual_USDT() external {
        uint256 depositAmt = 100_000e18;
        deal(USDT, client, depositAmt);
        _doDeposit(USDT, depositAmt);

        uint256 yieldAmt = 5_000e18;
        address donor = makeAddr("donor");
        deal(USDT, donor, yieldAmt);
        vm.startPrank(donor);
        IERC20(USDT).safeApprove(AAVE_POOL, yieldAmt);
        IAaveV3Pool(AAVE_POOL).supply(USDT, yieldAmt, proxyAddress, 0);
        vm.stopPrank();

        P2pAaveProxy proxy = P2pAaveProxy(proxyAddress);
        address aToken = proxy.getAToken(USDT);
        int256 accrued = proxy.calculateAccruedRewards(aToken, USDT);
        assertGt(accrued, 0, "should have accrued rewards");

        uint256 treasuryBefore = IERC20(USDT).balanceOf(P2P_TREASURY);
        vm.prank(p2pOperator);
        proxy.withdrawAccruedRewards(USDT);
        assertGt(IERC20(USDT).balanceOf(P2P_TREASURY), treasuryBefore, "treasury should receive fee");
    }

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

        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceAave, _asset, _amount, CLIENT_BPS, deadline, abi.encodePacked(r, s, v));
        vm.stopPrank();
    }
}
