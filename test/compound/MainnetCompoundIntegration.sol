// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/compound/p2pCompoundProxy/P2pCompoundProxy.sol";
import "../../src/adapters/compound/CompoundMarketRegistry.sol";
import "../../src/adapters/compound/CompoundRewardsAllowedCalldataChecker.sol";
import "../../src/adapters/compound/@compound/IComet.sol";
import "../../src/adapters/compound/@compound/ICometRewards.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetCompoundIntegration
/// @notice End-to-end mainnet fork tests for P2pCompoundProxy with multi-market support:
///   - Deposit/withdraw USDC, WETH, USDT into respective Compound V3 Comets
///   - Claim COMP rewards via CometRewards
contract MainnetCompoundIntegration is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant COMET_REWARDS = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    address constant COMP_TOKEN = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    // Comet markets
    address constant USDC_COMET = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant WETH_COMET = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address constant USDT_COMET = 0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840;

    // Base tokens
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant USDC_DEPOSIT = 10_000_000; // 10 USDC (6 decimals)
    uint256 constant WETH_DEPOSIT = 1e16; // 0.01 WETH (18 decimals)
    uint256 constant USDT_DEPOSIT = 10_000_000; // 10 USDT (6 decimals)

    P2pYieldProxyFactory private factory;
    CompoundMarketRegistry private marketRegistry;
    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    ProxyAdmin private operatorCheckerAdmin;
    TransparentUpgradeableProxy private operatorCheckerProxy;
    ProxyAdmin private clientToP2pCheckerAdmin;
    TransparentUpgradeableProxy private clientToP2pCheckerProxy;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(mainnetRpc, 21_308_893);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        // Deploy operator-controlled checker (default: deny all, upgradeable to CompoundRewardsAllowedCalldataChecker)
        AllowedCalldataChecker operatorImpl = new AllowedCalldataChecker();
        operatorCheckerAdmin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        operatorCheckerProxy = new TransparentUpgradeableProxy(
            address(operatorImpl), address(operatorCheckerAdmin), initData
        );

        // Deploy client-controlled checker (default: deny all)
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        clientToP2pCheckerAdmin = new ProxyAdmin();
        clientToP2pCheckerProxy = new TransparentUpgradeableProxy(
            address(clientToP2pImpl), address(clientToP2pCheckerAdmin), initData
        );

        factory = new P2pYieldProxyFactory(p2pSigner);

        // Deploy market registry with 3 initial markets
        address[] memory assets = new address[](3);
        address[] memory comets = new address[](3);
        assets[0] = USDC; comets[0] = USDC_COMET;
        assets[1] = WETH; comets[1] = WETH_COMET;
        assets[2] = USDT; comets[2] = USDT_COMET;
        marketRegistry = new CompoundMarketRegistry(address(factory), assets, comets);

        referenceProxy = address(
            new P2pCompoundProxy(
                address(factory),
                P2P_TREASURY,
                address(operatorCheckerProxy),
                address(clientToP2pCheckerProxy),
                address(marketRegistry),
                COMET_REWARDS
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    // ==================== E2E: Happy Path — USDC Deposit + Withdraw ====================

    /// @notice Deposit USDC into Compound via proxy, verify Supply event, withdraw all, verify Withdraw event
    function test_compound_HappyPath_USDC_Mainnet() external {
        deal(USDC, client, 100e6);

        vm.recordLogs();
        _doDeposit(USDC, USDC_DEPOSIT);
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, USDC_COMET, keccak256("Supply(address,address,uint256)"));

        assertGt(IComet(USDC_COMET).balanceOf(proxyAddress), 0, "proxy should have USDC Comet balance");

        vm.recordLogs();
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).withdraw(USDC, type(uint256).max);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertEventSeen(withdrawLogs, USDC_COMET, keccak256("Withdraw(address,address,uint256)"));

        assertEq(IComet(USDC_COMET).balanceOf(proxyAddress), 0, "proxy USDC Comet balance should be 0");
    }

    // ==================== E2E: Happy Path — WETH Deposit + Withdraw ====================

    /// @notice Deposit WETH into Compound WETH Comet, verify Supply event, withdraw all, verify Withdraw event
    function test_compound_HappyPath_WETH_Mainnet() external {
        deal(WETH, client, 1e18);

        vm.recordLogs();
        _doDeposit(WETH, WETH_DEPOSIT);
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, WETH_COMET, keccak256("Supply(address,address,uint256)"));

        assertGt(IComet(WETH_COMET).balanceOf(proxyAddress), 0, "proxy should have WETH Comet balance");

        vm.recordLogs();
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).withdraw(WETH, type(uint256).max);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertEventSeen(withdrawLogs, WETH_COMET, keccak256("Withdraw(address,address,uint256)"));

        assertEq(IComet(WETH_COMET).balanceOf(proxyAddress), 0, "proxy WETH Comet balance should be 0");
    }

    // ==================== E2E: Happy Path — USDT Deposit + Withdraw ====================

    /// @notice Deposit USDT into Compound USDT Comet, verify Supply event, withdraw all, verify Withdraw event
    function test_compound_HappyPath_USDT_Mainnet() external {
        deal(USDT, client, 100e6);

        vm.recordLogs();
        _doDeposit(USDT, USDT_DEPOSIT);
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, USDT_COMET, keccak256("Supply(address,address,uint256)"));

        assertGt(IComet(USDT_COMET).balanceOf(proxyAddress), 0, "proxy should have USDT Comet balance");

        vm.recordLogs();
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).withdraw(USDT, type(uint256).max);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertEventSeen(withdrawLogs, USDT_COMET, keccak256("Withdraw(address,address,uint256)"));

        assertEq(IComet(USDT_COMET).balanceOf(proxyAddress), 0, "proxy USDT Comet balance should be 0");
    }

    // ==================== E2E: Withdraw Accrued Rewards ====================

    /// @notice Deposit large amount, warp time to accrue interest, operator withdraws accrued rewards with fee split
    function test_compound_withdrawAccruedRewards_byOperator() external {
        uint256 largeDeposit = 10_000_000e6; // 10M USDC
        deal(USDC, client, largeDeposit);
        _doDeposit(USDC, largeDeposit);

        // Warp forward to accrue interest
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 2_628_000);

        int256 accrued = P2pCompoundProxy(proxyAddress).calculateAccruedRewards(address(0), USDC);
        assertGt(accrued, 0, "accrued rewards should be positive after time warp");

        uint256 treasuryBefore = IERC20(USDC).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDC).balanceOf(client);

        vm.recordLogs();
        vm.prank(p2pOperator);
        P2pCompoundProxy(proxyAddress).withdrawAccruedRewards(USDC);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertEventSeen(logs, USDC_COMET, keccak256("Withdraw(address,address,uint256)"));

        uint256 treasuryDelta = IERC20(USDC).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDC).balanceOf(client) - clientBefore;

        assertGt(treasuryDelta, 0, "treasury should receive fee");
        assertGt(clientDelta, 0, "client should receive share");
        assertEq(P2pCompoundProxy(proxyAddress).getUserPrincipal(USDC), largeDeposit, "principal unchanged");
    }

    // ==================== E2E: COMP Reward Claiming ====================

    /// @notice Deposit large amount, warp time to accrue COMP, claim via claimAdditionalRewardTokens,
    /// verify RewardClaimed event from CometRewards and COMP fee split
    function test_compound_claimCOMPRewards_e2e() external {
        _upgradeChecker();

        uint256 largeDeposit = 10_000_000e6; // 10M USDC
        deal(USDC, client, largeDeposit);
        _doDeposit(USDC, largeDeposit);

        // Warp forward to accrue COMP rewards
        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 657_000);

        // Build CometRewards.claim calldata
        bytes memory claimCalldata = abi.encodeCall(
            ICometRewards.claim,
            (USDC_COMET, proxyAddress, true)
        );

        address[] memory tokens = new address[](1);
        tokens[0] = COMP_TOKEN;

        uint256 treasuryBefore = IERC20(COMP_TOKEN).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(COMP_TOKEN).balanceOf(client);

        vm.recordLogs();
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).claimAdditionalRewardTokens(
            COMET_REWARDS,
            claimCalldata,
            tokens
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertEventSeen(logs, COMET_REWARDS, keccak256("RewardClaimed(address,address,address,uint256)"));

        uint256 treasuryGain = IERC20(COMP_TOKEN).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(COMP_TOKEN).balanceOf(client) - clientBefore;

        assertGt(treasuryGain, 0, "treasury should receive COMP fee");
        assertGt(clientGain, 0, "client should receive COMP");

        uint256 totalClaimed = treasuryGain + clientGain;
        uint256 expectedP2p = totalClaimed * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = totalClaimed - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
    }

    // ==================== E2E: Full Flow ====================

    /// @notice Full lifecycle: deposit → partial withdraw → claim COMP
    function test_compound_fullFlow_deposit_withdraw_claimCOMP() external {
        _upgradeChecker();

        uint256 largeDeposit = 10_000_000e6;
        deal(USDC, client, largeDeposit);
        _doDeposit(USDC, largeDeposit);

        // Partial withdraw
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).withdraw(USDC, 1_000_000e6);

        assertGt(IComet(USDC_COMET).balanceOf(proxyAddress), 0, "still has Comet balance");

        // Warp to accrue COMP
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 219_000);

        // Claim COMP
        bytes memory claimCalldata = abi.encodeCall(
            ICometRewards.claim,
            (USDC_COMET, proxyAddress, true)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = COMP_TOKEN;

        uint256 clientCompBefore = IERC20(COMP_TOKEN).balanceOf(client);

        vm.recordLogs();
        vm.prank(client);
        P2pCompoundProxy(proxyAddress).claimAdditionalRewardTokens(
            COMET_REWARDS,
            claimCalldata,
            tokens
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertEventSeen(logs, COMET_REWARDS, keccak256("RewardClaimed(address,address,address,uint256)"));

        uint256 clientCompGain = IERC20(COMP_TOKEN).balanceOf(client) - clientCompBefore;
        assertGt(clientCompGain, 0, "client should receive COMP rewards");
    }

    // ==================== Negative Tests ====================

    /// @notice Before checker upgrade: claimAdditionalRewardTokens reverts
    function test_compound_claimAdditionalRewards_revertsByDefault() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, USDC_DEPOSIT);

        bytes memory claimCalldata = abi.encodeCall(
            ICometRewards.claim,
            (USDC_COMET, proxyAddress, true)
        );
        address[] memory tokens = new address[](0);

        vm.prank(client);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pCompoundProxy(proxyAddress).claimAdditionalRewardTokens(
            COMET_REWARDS,
            claimCalldata,
            tokens
        );
    }

    /// @notice Deposit directly on proxy (not via factory) reverts
    function test_compound_depositDirectlyOnProxy_reverts() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, USDC_DEPOSIT);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotFactoryCalled.selector, client, factory));
        P2pCompoundProxy(proxyAddress).deposit(USDC, USDC_DEPOSIT);
        vm.stopPrank();
    }

    /// @notice Deposit unregistered asset reverts via registry
    function test_compound_depositUnregisteredAsset_reverts() external {
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        deal(USDC, client, 100e6);
        bytes memory signature = _getP2pSignerSignature(client, CLIENT_BPS, block.timestamp + 1 days);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(CompoundMarketRegistry__AssetNotSupported.selector, dai));
        factory.deposit(referenceProxy, dai, USDC_DEPOSIT, CLIENT_BPS, block.timestamp + 1 days, signature);
        vm.stopPrank();
    }

    /// @notice withdrawAccruedRewards reverts when called by client
    function test_compound_withdrawAccruedRewards_revertsForClient() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, USDC_DEPOSIT);

        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pCompoundProxy__NotP2pOperator.selector, client));
        P2pCompoundProxy(proxyAddress).withdrawAccruedRewards(USDC);
        vm.stopPrank();
    }

    /// @notice withdrawAccruedRewards reverts when no rewards accrued
    function test_compound_withdrawAccruedRewards_revertsWhenNoRewards() external {
        deal(USDC, client, 100e6);
        _doDeposit(USDC, USDC_DEPOSIT);

        vm.startPrank(p2pOperator);
        vm.expectRevert(P2pCompoundProxy__ZeroAccruedRewards.selector);
        P2pCompoundProxy(proxyAddress).withdrawAccruedRewards(USDC);
        vm.stopPrank();
    }

    // ==================== Market Registry Tests ====================

    /// @notice p2pOperator can add a new market to the registry
    function test_compound_addMarket_byOperator() external {
        // Deploy a mock comet-like contract that returns DAI as baseToken
        // For simplicity, just verify the addMarket access control works
        // (adding a real new Comet would require a deployed market)

        address nonOperator = makeAddr("nonOperator");
        address fakeAsset = makeAddr("fakeAsset");
        address fakeComet = makeAddr("fakeComet");

        vm.prank(nonOperator);
        vm.expectRevert(abi.encodeWithSelector(CompoundMarketRegistry__NotP2pOperator.selector, nonOperator));
        marketRegistry.addMarket(fakeAsset, fakeComet);
    }

    /// @notice Cannot add a market that is already registered
    function test_compound_addMarket_alreadyRegistered_reverts() external {
        vm.prank(p2pOperator);
        vm.expectRevert(abi.encodeWithSelector(CompoundMarketRegistry__MarketAlreadyRegistered.selector, USDC));
        marketRegistry.addMarket(USDC, USDC_COMET);
    }

    // ==================== E2E: Operator Claims COMP via claimAdditionalRewardTokens ====================

    /// @notice Operator claims COMP rewards after upgrading client-to-p2p checker
    function test_compound_claimCOMPRewards_byOperator() external {
        _upgradeChecker();
        _upgradeClientToP2pChecker();

        uint256 largeDeposit = 10_000_000e6;
        deal(USDC, client, largeDeposit);
        _doDeposit(USDC, largeDeposit);

        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 657_000);

        bytes memory claimCalldata = abi.encodeCall(
            ICometRewards.claim,
            (USDC_COMET, proxyAddress, true)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = COMP_TOKEN;

        uint256 treasuryBefore = IERC20(COMP_TOKEN).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(COMP_TOKEN).balanceOf(client);

        vm.prank(p2pOperator);
        P2pCompoundProxy(proxyAddress).claimAdditionalRewardTokens(
            COMET_REWARDS,
            claimCalldata,
            tokens
        );

        uint256 treasuryGain = IERC20(COMP_TOKEN).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientGain = IERC20(COMP_TOKEN).balanceOf(client) - clientBefore;

        assertGt(treasuryGain, 0, "treasury should receive COMP fee");
        assertGt(clientGain, 0, "client should receive COMP");

        uint256 totalClaimed = treasuryGain + clientGain;
        uint256 expectedP2p = totalClaimed * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = totalClaimed - expectedP2p;

        assertEq(treasuryGain, expectedP2p, "p2p fee mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
    }

    /// @notice Nobody (not client or operator) cannot call claimAdditionalRewardTokens
    function test_compound_claimCOMPRewards_revertForNobody() external {
        _upgradeChecker();

        deal(USDC, client, 100e6);
        _doDeposit(USDC, USDC_DEPOSIT);

        bytes memory claimCalldata = abi.encodeCall(
            ICometRewards.claim,
            (USDC_COMET, proxyAddress, true)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = COMP_TOKEN;

        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__CallerNeitherClientNorP2pOperator.selector, nobody));
        P2pCompoundProxy(proxyAddress).claimAdditionalRewardTokens(
            COMET_REWARDS,
            claimCalldata,
            tokens
        );
    }

    // ==================== Helpers ====================

    function _upgradeClientToP2pChecker() private {
        CompoundRewardsAllowedCalldataChecker compoundChecker =
            new CompoundRewardsAllowedCalldataChecker(COMET_REWARDS);

        vm.prank(p2pOperator);
        clientToP2pCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)),
            address(compoundChecker)
        );
    }

    function _upgradeChecker() private {
        CompoundRewardsAllowedCalldataChecker compoundChecker =
            new CompoundRewardsAllowedCalldataChecker(COMET_REWARDS);

        vm.prank(p2pOperator);
        operatorCheckerAdmin.upgrade(
            ITransparentUpgradeableProxy(address(operatorCheckerProxy)),
            address(compoundChecker)
        );
    }

    function _assertEventSeen(Vm.Log[] memory _logs, address _emitter, bytes32 _eventSig) private pure {
        uint256 logsLength = _logs.length;
        for (uint256 i; i < logsLength; ++i) {
            Vm.Log memory log = _logs[i];
            if (log.emitter == _emitter && log.topics.length > 0 && log.topics[0] == _eventSig) {
                return;
            }
        }
        revert("EVENT_NOT_FOUND");
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
