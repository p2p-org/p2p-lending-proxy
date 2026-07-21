// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/ethena/@ethena/IStakedUSDe.sol";
import "../../src/adapters/ethena/p2pEthenaProxy/P2pEthenaProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

/// @title MainnetEthenaIntegration
/// @notice End-to-end mainnet fork tests for P2pEthenaProxy covering both USDe→sUSDe and ENA→sENA:
///   - Deposit + cooldown + withdraw full lifecycle
///   - Operator accrued-rewards withdrawal with fee split
///   - Access control (only client can withdraw principal, only operator can withdraw accrued)
///   - Principal protection after operator claims rewards
contract MainnetEthenaIntegration is Test {
    using SafeERC20 for IERC20;

    // USDe / sUSDe
    address constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    // ENA / sENA
    address constant ENA = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address constant SENA = 0x8bE3460A480c80728a8C4D7a5D5303c85ba7B3b9;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant USDE_DEPOSIT = 1_000e18;
    uint256 constant ENA_DEPOSIT = 10_000e18;
    uint256 constant COOLDOWN_DURATION = 604_800; // 7 days

    P2pYieldProxyFactory private factory;
    address private referenceUsde;
    address private referenceEna;

    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private nobody;

    address private usdeProxyAddress;
    address private enaProxyAddress;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(mainnetRpc, 21_308_893);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker checkerImpl = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        // Operator checker
        ProxyAdmin operatorAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy operatorChecker = new TransparentUpgradeableProxy(
            address(checkerImpl), address(operatorAdmin), initData
        );

        // Client-to-p2p checker
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pChecker = new TransparentUpgradeableProxy(
            address(clientToP2pImpl), address(clientToP2pAdmin), initData
        );

        factory = new P2pYieldProxyFactory(p2pSigner);

        // Reference proxy for USDe → sUSDe
        referenceUsde = address(
            new P2pEthenaProxy(
                address(factory), P2P_TREASURY,
                address(operatorChecker), address(clientToP2pChecker),
                SUSDE, USDE
            )
        );
        factory.addReferenceP2pYieldProxy(referenceUsde);

        // Reference proxy for ENA → sENA (same contract, different immutables)
        referenceEna = address(
            new P2pEthenaProxy(
                address(factory), P2P_TREASURY,
                address(operatorChecker), address(clientToP2pChecker),
                SENA, ENA
            )
        );
        factory.addReferenceP2pYieldProxy(referenceEna);

        vm.stopPrank();

        usdeProxyAddress = factory.predictP2pYieldProxyAddress(referenceUsde, client, CLIENT_BPS);
        enaProxyAddress = factory.predictP2pYieldProxyAddress(referenceEna, client, CLIENT_BPS);
    }

    // ==================== USDe: Deposit + Cooldown + Withdraw ====================

    function test_ethena_HappyPath_USDe_Mainnet() external {
        deal(USDE, client, 10_000e18);
        _doDeposit(referenceUsde, USDE, USDE_DEPOSIT, usdeProxyAddress);

        uint256 shares = IERC20(SUSDE).balanceOf(usdeProxyAddress);
        assertGt(shares, 0, "proxy should hold sUSDe shares");

        // cooldown → warp → withdraw
        vm.prank(client);
        P2pEthenaProxy(usdeProxyAddress).cooldownShares(shares);

        _warpCooldown();

        uint256 clientBefore = IERC20(USDE).balanceOf(client);
        vm.prank(client);
        P2pEthenaProxy(usdeProxyAddress).withdrawAfterCooldown();

        uint256 clientAfter = IERC20(USDE).balanceOf(client);
        assertGt(clientAfter, clientBefore, "client should receive USDe after cooldown");
    }

    // ==================== ENA: Deposit + Cooldown + Withdraw ====================

    function test_ethena_HappyPath_ENA_Mainnet() external {
        deal(ENA, client, 100_000e18);
        _doDeposit(referenceEna, ENA, ENA_DEPOSIT, enaProxyAddress);

        uint256 shares = IERC20(SENA).balanceOf(enaProxyAddress);
        assertGt(shares, 0, "proxy should hold sENA shares");

        // cooldown → warp → withdraw
        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).cooldownShares(shares);

        _warpCooldown();

        uint256 clientBefore = IERC20(ENA).balanceOf(client);
        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldown();

        uint256 clientAfter = IERC20(ENA).balanceOf(client);
        assertGt(clientAfter, clientBefore, "client should receive ENA after cooldown");
    }

    // ==================== Operator: Withdraw Accrued Rewards — USDe ====================

    function test_ethena_withdrawAccruedRewards_USDe_byOperator() external {
        deal(USDE, client, 10_000e18);
        _doDeposit(referenceUsde, USDE, USDE_DEPOSIT, usdeProxyAddress);

        // Simulate yield by dealing extra USDe to sUSDe vault (increases share price)
        _simulateYield(USDE, SUSDE, 500e18);

        int256 accrued = P2pEthenaProxy(usdeProxyAddress).calculateAccruedRewards(SUSDE, USDE);
        assertGt(accrued, 0, "accrued rewards should be positive after yield");

        uint256 treasuryBefore = IERC20(USDE).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(USDE).balanceOf(client);

        // Operator cooldown + warp + withdraw accrued
        vm.prank(p2pOperator);
        P2pEthenaProxy(usdeProxyAddress).cooldownAssetsAccruedRewards();

        _warpCooldown();

        vm.prank(p2pOperator);
        P2pEthenaProxy(usdeProxyAddress).withdrawAfterCooldownAccruedRewards();

        uint256 treasuryDelta = IERC20(USDE).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(USDE).balanceOf(client) - clientBefore;

        assertGt(treasuryDelta, 0, "treasury should receive fee");
        assertGt(clientDelta, 0, "client should receive share");

        // Verify fee split (1 wei tolerance for rounding)
        uint256 totalDistributed = treasuryDelta + clientDelta;
        uint256 expectedP2p = totalDistributed * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = totalDistributed - expectedP2p;
        assertApproxEqAbs(treasuryDelta, expectedP2p, 1, "p2p fee mismatch");
        assertApproxEqAbs(clientDelta, expectedClient, 1, "client amount mismatch");
    }

    // ==================== Operator: Withdraw Accrued Rewards — ENA ====================

    function test_ethena_withdrawAccruedRewards_ENA_byOperator() external {
        deal(ENA, client, 100_000e18);
        _doDeposit(referenceEna, ENA, ENA_DEPOSIT, enaProxyAddress);

        _simulateYield(ENA, SENA, 5_000e18);

        int256 accrued = P2pEthenaProxy(enaProxyAddress).calculateAccruedRewards(SENA, ENA);
        assertGt(accrued, 0, "accrued rewards should be positive");

        uint256 treasuryBefore = IERC20(ENA).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(ENA).balanceOf(client);

        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).cooldownAssetsAccruedRewards();

        _warpCooldown();

        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldownAccruedRewards();

        uint256 treasuryDelta = IERC20(ENA).balanceOf(P2P_TREASURY) - treasuryBefore;
        uint256 clientDelta = IERC20(ENA).balanceOf(client) - clientBefore;

        assertGt(treasuryDelta, 0, "treasury should receive ENA fee");
        assertGt(clientDelta, 0, "client should receive ENA share");

        uint256 totalDistributed = treasuryDelta + clientDelta;
        uint256 expectedP2p = totalDistributed * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = totalDistributed - expectedP2p;
        assertApproxEqAbs(treasuryDelta, expectedP2p, 1, "p2p fee mismatch");
        assertApproxEqAbs(clientDelta, expectedClient, 1, "client amount mismatch");
    }

    // ==================== Principal Protection — USDe ====================

    function test_ethena_principalProtection_USDe() external {
        deal(USDE, client, 10_000e18);
        _doDeposit(referenceUsde, USDE, USDE_DEPOSIT, usdeProxyAddress);

        _simulateYield(USDE, SUSDE, 200e18);

        // Operator takes accrued rewards
        vm.prank(p2pOperator);
        P2pEthenaProxy(usdeProxyAddress).cooldownAssetsAccruedRewards();
        _warpCooldown();
        vm.prank(p2pOperator);
        P2pEthenaProxy(usdeProxyAddress).withdrawAfterCooldownAccruedRewards();

        // Client withdraws remaining principal
        uint256 shares = IERC20(SUSDE).balanceOf(usdeProxyAddress);
        vm.prank(client);
        P2pEthenaProxy(usdeProxyAddress).cooldownShares(shares);
        _warpCooldown();

        uint256 clientBefore = IERC20(USDE).balanceOf(client);
        uint256 treasuryBefore = IERC20(USDE).balanceOf(P2P_TREASURY);
        vm.prank(client);
        P2pEthenaProxy(usdeProxyAddress).withdrawAfterCooldown();
        uint256 clientPrincipal = IERC20(USDE).balanceOf(client) - clientBefore;
        uint256 treasuryGain = IERC20(USDE).balanceOf(P2P_TREASURY) - treasuryBefore;

        // Client receives at least principal (may include residual yield from ERC4626 rounding)
        assertGe(clientPrincipal, USDE_DEPOSIT - 2, "client should receive back at least principal");
        // Treasury gets at most its share of residual yield, not principal
        uint256 residualYield = clientPrincipal > USDE_DEPOSIT ? clientPrincipal - USDE_DEPOSIT : 0;
        uint256 maxTreasuryFromResidual = (residualYield + treasuryGain) * (10_000 - CLIENT_BPS) / 10_000 + 2;
        assertLe(treasuryGain, maxTreasuryFromResidual, "treasury should only take from residual yield");
    }

    // ==================== Principal Protection — ENA ====================

    function test_ethena_principalProtection_ENA() external {
        deal(ENA, client, 100_000e18);
        _doDeposit(referenceEna, ENA, ENA_DEPOSIT, enaProxyAddress);

        _simulateYield(ENA, SENA, 2_000e18);

        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).cooldownAssetsAccruedRewards();
        _warpCooldown();
        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldownAccruedRewards();

        uint256 shares = IERC20(SENA).balanceOf(enaProxyAddress);
        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).cooldownShares(shares);
        _warpCooldown();

        uint256 clientBefore = IERC20(ENA).balanceOf(client);
        uint256 treasuryBefore = IERC20(ENA).balanceOf(P2P_TREASURY);
        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldown();
        uint256 clientPrincipal = IERC20(ENA).balanceOf(client) - clientBefore;
        uint256 treasuryGain = IERC20(ENA).balanceOf(P2P_TREASURY) - treasuryBefore;

        assertGe(clientPrincipal, ENA_DEPOSIT - 2, "client should receive back at least ENA principal");
        uint256 residualYield = clientPrincipal > ENA_DEPOSIT ? clientPrincipal - ENA_DEPOSIT : 0;
        uint256 maxTreasuryFromResidual = (residualYield + treasuryGain) * (10_000 - CLIENT_BPS) / 10_000 + 2;
        assertLe(treasuryGain, maxTreasuryFromResidual, "treasury should only take from residual yield");
    }

    // ==================== Access Control: Only Client Can Withdraw ====================

    function test_ethena_onlyClient_canWithdraw_USDe() external {
        deal(USDE, client, 10_000e18);
        _doDeposit(referenceUsde, USDE, USDE_DEPOSIT, usdeProxyAddress);

        // operator cannot cooldownAssets
        vm.prank(p2pOperator);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, p2pOperator, client));
        P2pEthenaProxy(usdeProxyAddress).cooldownAssets(100e18);

        // nobody cannot cooldownAssets
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, nobody, client));
        P2pEthenaProxy(usdeProxyAddress).cooldownAssets(100e18);

        // nobody cannot cooldownShares
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, nobody, client));
        P2pEthenaProxy(usdeProxyAddress).cooldownShares(1e18);
    }

    function test_ethena_onlyClient_canWithdraw_ENA() external {
        deal(ENA, client, 100_000e18);
        _doDeposit(referenceEna, ENA, ENA_DEPOSIT, enaProxyAddress);

        vm.prank(p2pOperator);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, p2pOperator, client));
        P2pEthenaProxy(enaProxyAddress).cooldownAssets(100e18);

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, nobody, client));
        P2pEthenaProxy(enaProxyAddress).cooldownShares(1e18);
    }

    // ==================== Access Control: Only Operator Can Withdraw Accrued ====================

    function test_ethena_onlyOperator_canWithdrawAccrued_USDe() external {
        deal(USDE, client, 10_000e18);
        _doDeposit(referenceUsde, USDE, USDE_DEPOSIT, usdeProxyAddress);
        _simulateYield(USDE, SUSDE, 100e18);

        // client cannot
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pEthenaProxy__NotP2pOperator.selector, client));
        P2pEthenaProxy(usdeProxyAddress).cooldownAssetsAccruedRewards();

        // nobody cannot
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pEthenaProxy__NotP2pOperator.selector, nobody));
        P2pEthenaProxy(usdeProxyAddress).cooldownAssetsAccruedRewards();
    }

    // ==================== Deposit Unsupported Asset ====================

    function test_ethena_depositUnsupportedAsset_reverts() external {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        deal(USDE, client, 10_000e18);

        bytes memory sig = _getSignature(referenceUsde, client, CLIENT_BPS, block.timestamp + 1 days);
        vm.startPrank(client);
        vm.expectRevert(abi.encodeWithSelector(P2pEthenaProxy__InvalidDepositAsset.selector, usdc));
        factory.deposit(referenceUsde, usdc, 1e6, CLIENT_BPS, block.timestamp + 1 days, sig);
        vm.stopPrank();
    }

    // ==================== Full Flow: Deposit + Yield + Operator Claim + Client Withdraw ====================

    function test_ethena_fullFlow_ENA_Mainnet() external {
        deal(ENA, client, 100_000e18);
        _doDeposit(referenceEna, ENA, ENA_DEPOSIT, enaProxyAddress);

        // Simulate yield
        _simulateYield(ENA, SENA, 3_000e18);

        // Operator claims accrued
        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).cooldownAssetsAccruedRewards();
        _warpCooldown();
        vm.prank(p2pOperator);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldownAccruedRewards();

        // Client full withdraw
        uint256 shares = IERC20(SENA).balanceOf(enaProxyAddress);
        assertGt(shares, 0, "proxy should still hold shares after operator claim");

        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).cooldownShares(shares);
        _warpCooldown();

        vm.prank(client);
        P2pEthenaProxy(enaProxyAddress).withdrawAfterCooldown();

        assertEq(IERC20(SENA).balanceOf(enaProxyAddress), 0, "proxy should have no shares left");
        assertEq(P2pEthenaProxy(enaProxyAddress).getUserPrincipal(ENA), 0, "principal should be zero");
    }

    // ==================== Helpers ====================

    function _doDeposit(address _ref, address _asset, uint256 _amount, address _proxyAddr) private {
        bytes memory sig = _getSignature(_ref, client, CLIENT_BPS, block.timestamp + 1 days);

        vm.startPrank(client);
        IERC20(_asset).safeApprove(_proxyAddr, 0);
        IERC20(_asset).safeApprove(_proxyAddr, type(uint256).max);
        factory.deposit(_ref, _asset, _amount, CLIENT_BPS, block.timestamp + 1 days, sig);
        vm.stopPrank();
    }

    function _getSignature(address _ref, address _client, uint96 _bps, uint256 _deadline)
        private
        view
        returns (bytes memory)
    {
        bytes32 hash = factory.getHashForP2pSigner(_ref, _client, _bps, _deadline);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _simulateYield(address _asset, address _vault, uint256 _yieldAmount) private {
        deal(_asset, _vault, IERC20(_asset).balanceOf(_vault) + _yieldAmount);
    }

    function _warpCooldown() private {
        vm.warp(block.timestamp + COOLDOWN_DURATION + 1);
        vm.roll(block.number + (COOLDOWN_DURATION / 12));
    }
}
