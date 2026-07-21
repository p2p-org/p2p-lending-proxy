// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/access/P2pOperator.sol";
import "../../src/adapters/aave/p2pAaveProxy/P2pAaveProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/adapters/aave/@aave/IAaveV3Pool.sol";
import "../../src/p2pYieldProxy/P2pYieldProxy.sol";
import "../../src/p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetAaveIntegration is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000; // 10 USDC/USDT

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;
    address private allowedChecker;
    address private referenceProxy;
    address private proxyAddress;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(mainnetRpc, 21_308_893);

        client = makeAddr("client");
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
            new P2pAaveProxy(
                address(factory),
                P2P_TREASURY,
                address(checkerProxy),
                address(clientToP2pCheckerProxy),
                AAVE_POOL,
                AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        allowedChecker = address(checkerProxy);
        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    function test_aave_HappyPath_USDC_Mainnet() external {
        deal(USDC, client, 100e6);

        vm.recordLogs();
        _doDeposit(USDC, DEPOSIT_AMOUNT);
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertAaveEventSeen(depositLogs, keccak256("Supply(address,address,address,uint256,uint16)"));

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDC);
        assertGt(IERC20(aToken).balanceOf(proxyAddress), 0);

        vm.recordLogs();
        vm.prank(client);
        P2pAaveProxy(proxyAddress).withdraw(USDC, type(uint256).max);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertAaveEventSeen(withdrawLogs, keccak256("Withdraw(address,address,address,uint256)"));

        assertEq(IERC20(aToken).balanceOf(proxyAddress), 0);
    }

    function test_aave_HappyPath_USDT_Mainnet() external {
        deal(USDT, client, 100e6);
        _doDeposit(USDT, DEPOSIT_AMOUNT);

        address aToken = P2pAaveProxy(proxyAddress).getAToken(USDT);
        assertGt(IERC20(aToken).balanceOf(proxyAddress), 0);

        vm.prank(client);
        P2pAaveProxy(proxyAddress).withdraw(USDT, type(uint256).max);

        assertEq(IERC20(aToken).balanceOf(proxyAddress), 0);
    }

    function test_aave_withdrawAccruedRewards_byOperator() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, DEPOSIT_AMOUNT);

        uint256 simulatedReward = 2e6;
        address donor = makeAddr("donor");
        deal(USDC, donor, simulatedReward);
        vm.startPrank(donor);
        IERC20(USDC).safeApprove(AAVE_POOL, simulatedReward);
        IAaveV3Pool(AAVE_POOL).supply(USDC, simulatedReward, proxyAddress, 0);
        vm.stopPrank();

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.recordLogs();
        vm.prank(p2pOperator);
        P2pAaveProxy(proxyAddress).withdrawAccruedRewards(USDC);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertAaveEventSeen(withdrawLogs, keccak256("Withdraw(address,address,address,uint256)"));

        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;

        assertGt(treasuryDelta, 0);
        assertGt(clientDelta, 0);
        assertEq(P2pAaveProxy(proxyAddress).getUserPrincipal(USDC), DEPOSIT_AMOUNT);
    }

    function test_aave_withdrawAccruedRewards_revertsForClient() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, DEPOSIT_AMOUNT);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pAaveProxy__NotP2pOperator.selector, client));
        P2pAaveProxy(proxyAddress).withdrawAccruedRewards(USDC);
        vm.stopPrank();
    }

    function test_aave_withdrawAccruedRewards_revertsWhenNoRewards() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, DEPOSIT_AMOUNT);

        vm.startPrank(p2pOperator);
        vm.expectRevert(P2pAaveProxy__ZeroAccruedRewards.selector);
        P2pAaveProxy(proxyAddress).withdrawAccruedRewards(USDC);
        vm.stopPrank();
    }

    function test_aave_transferP2pSigner() external {
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        vm.startPrank(p2pOperator);
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        assertEq(factory.getP2pSigner(), nobody);
    }

    function test_aave_p2pSignerSignatureExpired() external {
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory signature = _getP2pSignerSignature(client, CLIENT_BPS, expiredDeadline);

        deal(USDC, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(USDC).safeApprove(proxyAddress, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(P2pYieldProxyFactory__P2pSignerSignatureExpired.selector, expiredDeadline)
        );
        factory.deposit(referenceProxy, USDC, DEPOSIT_AMOUNT, CLIENT_BPS, expiredDeadline, signature);
        vm.stopPrank();
    }

    function test_aave_invalidP2pSignerSignature() external {
        uint256 sigDeadline = block.timestamp + 1 days;
        bytes memory signature = _getP2pSignerSignature(client, CLIENT_BPS + 1, sigDeadline);

        deal(USDC, client, DEPOSIT_AMOUNT);
        vm.startPrank(client);
        IERC20(USDC).safeApprove(proxyAddress, type(uint256).max);
        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);
        factory.deposit(referenceProxy, USDC, DEPOSIT_AMOUNT, CLIENT_BPS, sigDeadline, signature);
        vm.stopPrank();
    }

    function test_aave_depositDirectlyOnProxy_reverts() external {
        deal(USDC, client, DEPOSIT_AMOUNT);
        _doDeposit(USDC, DEPOSIT_AMOUNT);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotFactoryCalled.selector, client, factory));
        P2pAaveProxy(proxyAddress).deposit(USDC, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_aave_depositUnsupportedAsset_reverts() external {
        address unsupportedAsset = makeAddr("unsupportedAsset");
        deal(USDC, client, DEPOSIT_AMOUNT);
        bytes memory signature = _getP2pSignerSignature(client, CLIENT_BPS, block.timestamp + 1 days);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pAaveLikeProxy__AssetNotSupported.selector, unsupportedAsset));
        factory.deposit(referenceProxy, unsupportedAsset, DEPOSIT_AMOUNT, CLIENT_BPS, block.timestamp + 1 days, signature);
        vm.stopPrank();
    }

    function test_aave_callAnyFunction_revertsByDefault() external {
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        AllowedCalldataChecker(allowedChecker).checkCalldata(
            AAVE_POOL,
            IAaveV3Pool.supply.selector,
            abi.encode(USDC, DEPOSIT_AMOUNT, proxyAddress, 0)
        );
    }

    function test_aave_acceptP2pOperator() external {
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

        vm.startPrank(newOperator);
        factory.acceptP2pOperator();
        vm.stopPrank();

        assertEq(factory.getP2pOperator(), newOperator);
        assertEq(factory.getPendingP2pOperator(), address(0));
    }

    function _assertAaveEventSeen(Vm.Log[] memory _logs, bytes32 _eventSig) private pure {
        uint256 logsLength = _logs.length;
        for (uint256 i; i < logsLength; ++i) {
            Vm.Log memory log = _logs[i];
            if (log.emitter == AAVE_POOL && log.topics.length > 0 && log.topics[0] == _eventSig) {
                return;
            }
        }
        revert("AAVE_EVENT_NOT_FOUND");
    }

    function _doDeposit(address _asset, uint256 _amount) private {
        uint256 sigDeadline = block.timestamp + 1 days;
        bytes memory signerSignature = _getP2pSignerSignature(client, CLIENT_BPS, sigDeadline);

        vm.startPrank(client);
        IERC20(_asset).safeApprove(proxyAddress, 0);
        IERC20(_asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, _asset, _amount, CLIENT_BPS, sigDeadline, signerSignature);
        vm.stopPrank();
    }

    function _getP2pSignerSignature(address _client, uint96 _clientBasisPoints, uint256 _sigDeadline)
        private
        view
        returns (bytes memory)
    {
        bytes32 hashForSigner = factory.getHashForP2pSigner(referenceProxy, _client, _clientBasisPoints, _sigDeadline);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}
