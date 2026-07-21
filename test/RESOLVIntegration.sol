// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/access/P2pOperator.sol";
import "../src/adapters/resolv/p2pResolvProxy/P2pResolvProxy.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "./mock/IERC20Rebasing.sol";
import "../src/adapters/resolv/@resolv/IResolvStaking.sol";
import "../src/adapters/resolv/@resolv/IStUSR.sol";
import "../src/adapters/resolv/@resolv/IStakedTokenDistributor.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";


contract RESOLVIntegration is Test {
    using SafeERC20 for IERC20;

    event P2pResolvProxy__StakedTokenDistributorUpdated(address indexed previousStakedTokenDistributor, address indexed newStakedTokenDistributor);
    event P2pResolvProxy__RewardTokenSwept(address indexed token, uint256 amount);
    event P2pResolvProxy__RewardTokensClaimed(
        address indexed token,
        uint256 amount,
        uint256 p2pAmount,
        uint256 clientAmount
    );

    address constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address constant stUSR = 0x6c8984bc7DBBeDAf4F6b2FD766f16eBB7d10AAb4;
    address constant RESOLV = 0x259338656198eC7A76c729514D3CB45Dfbf768A1;
    address constant stRESOLV = 0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23;
    address constant P2pTreasury = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;
    address constant StakedTokenDistributor = 0xCE9d50db432e0702BcAd5a4A9122F1F8a77aD8f9;

    P2pYieldProxyFactory private factory;
    address private referenceProxy;

    address private clientAddress;
    uint256 private clientPrivateKey;

    address private p2pSignerAddress;
    uint256 private p2pSignerPrivateKey;

    address private p2pOperatorAddress;
    address private nobody;

    uint256 constant SigDeadline = 1752690907;
    uint96 constant ClientBasisPoints = 8700; // 13% fee
    uint256 constant DepositAmount = 10 ether;

    address proxyAddress;

    uint48 nonce;

    function setUp() public {
        vm.createSelectFork("mainnet", 22798925);

        (clientAddress, clientPrivateKey) = makeAddrAndKey("client");
        (p2pSignerAddress, p2pSignerPrivateKey) = makeAddrAndKey("p2pSigner");
        p2pOperatorAddress = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperatorAddress);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy tup = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pTup = new TransparentUpgradeableProxy(
            address(clientToP2pImpl),
            address(clientToP2pAdmin),
            initData
        );
        factory = new P2pYieldProxyFactory(p2pSignerAddress);
        referenceProxy = address(
            new P2pResolvProxy(
                address(factory),
                P2pTreasury,
                address(tup),
                address(clientToP2pTup),
                stUSR,
                USR,
                stRESOLV,
                RESOLV
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints);
    }

    function test_resolv_Resolv_happyPath_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 10000e18);

        uint256 assetBalanceBefore = IERC20(RESOLV).balanceOf(clientAddress);

        _doDeposit();

        uint256 assetBalanceAfter1 = IERC20(RESOLV).balanceOf(clientAddress);
        assertEq(assetBalanceBefore - assetBalanceAfter1, DepositAmount);

        _doDeposit();

        uint256 assetBalanceAfter2 = IERC20(RESOLV).balanceOf(clientAddress);
        assertEq(assetBalanceAfter1 - assetBalanceAfter2, DepositAmount);

        _doDeposit();
        _doDeposit();

        _doWithdraw(10);
        _doWithdraw(5);
        _doWithdraw(3);
        _doWithdraw(2);
        _doWithdraw(1);

        uint256 assetBalanceAfterAllWithdrawals = IERC20(RESOLV).balanceOf(clientAddress);

        assertApproxEqAbs(
            assetBalanceAfterAllWithdrawals,
            assetBalanceBefore,
            1e9,
            "Client should recover principal"
        );
    }

    function test_resolv_claimRewardTokens_splitsRewards() public {
        uint256 depositAmount = 10 ether;
        (address localProxy, MockERC20 mockResolv, MockResolvStaking mockStResolv) =
            _setupMockResolvEnvironment(depositAmount);
        mockResolv.totalSupply();

        MockERC20 extraReward = new MockERC20("Extra", "EXTRA");
        mockStResolv.addRewardToken(address(extraReward));
        mockStResolv.setRewardTokenAmount(address(extraReward), localProxy, 5 ether);

        uint256 treasuryBalanceBefore = extraReward.balanceOf(P2pTreasury);
        uint256 clientBalanceBefore = extraReward.balanceOf(clientAddress);

        vm.startPrank(p2pOperatorAddress);
        P2pResolvProxy(localProxy).claimRewardTokens();
        vm.stopPrank();

        uint256 treasuryBalanceAfter = extraReward.balanceOf(P2pTreasury);
        uint256 clientBalanceAfter = extraReward.balanceOf(clientAddress);

        uint256 rewardAmount = 5 ether;
        uint256 expectedTreasury = (rewardAmount * (10_000 - ClientBasisPoints) + 9999) / 10_000;
        uint256 expectedClient = rewardAmount - expectedTreasury;

        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedTreasury, "treasury share mismatch");
        assertEq(clientBalanceAfter - clientBalanceBefore, expectedClient, "client share mismatch");
    }

    function test_resolv_claimStakedTokenDistributor_rewardsWithdrawnWithSplit() public {
        uint256 depositAmount = 20 ether;
        (address localProxy, MockERC20 mockResolv, MockResolvStaking mockStResolv) =
            _setupMockResolvEnvironment(depositAmount);

        MockStakedTokenDistributor distributor = new MockStakedTokenDistributor(mockResolv, mockStResolv);

        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(localProxy).setStakedTokenDistributor(address(distributor));

        uint256 airdropAmount = 5 ether;
        bytes32[] memory proof = new bytes32[](0);
        vm.startPrank(p2pOperatorAddress);
        P2pResolvProxy(localProxy).claimStakedTokenDistributor(0, airdropAmount, proof);
        vm.stopPrank();

        uint256 treasuryBalanceBefore = mockResolv.balanceOf(P2pTreasury);
        uint256 clientBalanceBefore = mockResolv.balanceOf(clientAddress);

        vm.prank(clientAddress);
        P2pResolvProxy(localProxy).withdrawRESOLV();

        uint256 treasuryBalanceAfter = mockResolv.balanceOf(P2pTreasury);
        uint256 clientBalanceAfter = mockResolv.balanceOf(clientAddress);

        uint256 expectedTreasury = (airdropAmount * (10_000 - ClientBasisPoints) + 9999) / 10_000;
        uint256 expectedClient = airdropAmount - expectedTreasury;

        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedTreasury, "treasury reward share mismatch");
        assertEq(clientBalanceAfter - clientBalanceBefore, expectedClient, "client reward share mismatch");
    }

    function test_resolv_withdrawRESOLV_principalAndAirdropOnlyFeesRewards() public {
        uint256 depositAmount = 12 ether;
        (address localProxy, MockERC20 mockResolv, MockResolvStaking mockStResolv) =
            _setupMockResolvEnvironment(depositAmount);

        MockStakedTokenDistributor distributor = new MockStakedTokenDistributor(mockResolv, mockStResolv);
        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(localProxy).setStakedTokenDistributor(address(distributor));

        uint256 airdropAmount = 3 ether;
        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(localProxy).claimStakedTokenDistributor(0, airdropAmount, new bytes32[](0));

        vm.prank(clientAddress);
        P2pResolvProxy(localProxy).initiateWithdrawalRESOLV(depositAmount);

        uint256 treasuryBefore = mockResolv.balanceOf(P2pTreasury);
        uint256 clientBefore = mockResolv.balanceOf(clientAddress);

        vm.prank(clientAddress);
        P2pResolvProxy(localProxy).withdrawRESOLV();

        uint256 treasuryAfter = mockResolv.balanceOf(P2pTreasury);
        uint256 clientAfter = mockResolv.balanceOf(clientAddress);

        uint256 expectedFee = (airdropAmount * (10_000 - ClientBasisPoints) + 9999) / 10_000;
        uint256 expectedClient = depositAmount + (airdropAmount - expectedFee);

        assertEq(treasuryAfter - treasuryBefore, expectedFee, "treasury should only fee rewards");
        assertEq(clientAfter - clientBefore, expectedClient, "client receives principal plus net rewards");
    }

    function test_resolv_mainnet_claimRewardTokens_for_known_proxy_address() public {
        address knownProxy = 0x3F888f4E16a08C6B3745dDbaDe98e24569852FA4;

        uint256 beforeBal = IERC20(RESOLV).balanceOf(knownProxy);
        uint256 claimable = IResolvStaking(stRESOLV).getUserClaimableAmounts(knownProxy, RESOLV);

        vm.prank(knownProxy);
        IResolvStaking(stRESOLV).claim(knownProxy, knownProxy);

        uint256 afterBal = IERC20(RESOLV).balanceOf(knownProxy);

        assertEq(afterBal - beforeBal, claimable, "claim delta should match claimable");
        if (claimable > 0) {
            assertGt(afterBal, beforeBal, "expected RESOLV rewards transferred");
        }
    }

    function test_resolv_claimRewardTokens_via_proxy() public {
        deal(RESOLV, clientAddress, DepositAmount);
        _doDeposit();

        uint256 claimable = IResolvStaking(stRESOLV).getUserClaimableAmounts(proxyAddress, RESOLV);
        uint256 beforeBal = IERC20(RESOLV).balanceOf(proxyAddress);

        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(proxyAddress).claimRewardTokens();

        uint256 afterBal = IERC20(RESOLV).balanceOf(proxyAddress);

        assertEq(afterBal - beforeBal, claimable, "proxy RESOLV delta should match claimable");
        if (claimable > 0) {
            assertGt(afterBal, beforeBal, "proxy should receive rewards");
        }
    }

    function test_resolv_claimRewardTokens_via_etched_proxy() public {
        vm.createSelectFork("mainnet", 23_866_064);
        // Use the known mainnet stRESOLV and a real proxy address that may have rewards
        address knownProxy = 0x3F888f4E16a08C6B3745dDbaDe98e24569852FA4;

        // Deploy a fresh proxy to extract runtime code with correct immutables
        AllowedCalldataChecker checker = new AllowedCalldataChecker();
        checker.initialize();
        AllowedCalldataChecker clientToP2pChecker = new AllowedCalldataChecker();
        clientToP2pChecker.initialize();

        P2pResolvProxy fresh = new P2pResolvProxy(
            address(this),
            P2pTreasury,
            address(checker),
            address(clientToP2pChecker),
            stUSR,
            USR,
            stRESOLV,
            RESOLV
        );

        // Replace code at known proxy address
        vm.etch(knownProxy, address(fresh).code);

        // Initialize storage so modifiers pass and fee math works
        vm.prank(address(this));
        P2pResolvProxy(knownProxy).initialize(clientAddress, ClientBasisPoints);

        vm.prank(knownProxy);
        IResolvStaking(stRESOLV).updateCheckpoint(knownProxy);

        uint256 claimable = IResolvStaking(stRESOLV).getUserClaimableAmounts(knownProxy, RESOLV);
        require(claimable > 0, "no claimable rewards at fork block");
        uint256 clientBefore = IERC20(RESOLV).balanceOf(clientAddress);
        uint256 treasuryBefore = IERC20(RESOLV).balanceOf(P2pTreasury);

        uint256 expectedP2p = (claimable * (10_000 - ClientBasisPoints) + 9999) / 10_000;
        uint256 expectedClient = claimable - expectedP2p;
        vm.expectEmit(true, false, false, true, knownProxy);
        emit P2pResolvProxy__RewardTokensClaimed(RESOLV, claimable, expectedP2p, expectedClient);

        vm.prank(clientAddress);
        P2pResolvProxy(knownProxy).claimRewardTokens();

        uint256 clientAfter = IERC20(RESOLV).balanceOf(clientAddress);
        uint256 treasuryAfter = IERC20(RESOLV).balanceOf(P2pTreasury);

        assertEq(clientAfter + treasuryAfter - clientBefore - treasuryBefore, claimable, "claimed amount mismatch");
        if (claimable > 0) {
            assertGt(clientAfter, clientBefore, "client should receive rewards");
        }
    }

    function test_resolv_calculateAccruedRewards_doesNotCountEffectiveBoost() public {
        uint256 depositAmount = 10 ether;
        (address localProxy, MockERC20 mockResolv, MockResolvStaking mockStResolv) =
            _setupMockResolvEnvironment(depositAmount);
        mockResolv.totalSupply(); // touch to silence unused variable warning

        mockStResolv.setOverrideEffectiveBalance(localProxy, depositAmount * 2);

        assertEq(
            P2pResolvProxy(localProxy).calculateAccruedRewardsRESOLV(RESOLV),
            0,
            "effective balance boost should not be treated as profit"
        );
    }

    function test_resolv_withdrawRESOLV_noFeesWhenOnlyEffectiveBoost() public {
        uint256 depositAmount = 8 ether;
        (address localProxy, MockERC20 mockResolv, MockResolvStaking mockStResolv) =
            _setupMockResolvEnvironment(depositAmount);

        mockStResolv.setOverrideEffectiveBalance(localProxy, depositAmount * 3);

        uint256 treasuryBefore = mockResolv.balanceOf(P2pTreasury);

        vm.startPrank(clientAddress);
        uint256 shares = IERC20(address(mockStResolv)).balanceOf(localProxy);
        P2pResolvProxy(localProxy).initiateWithdrawalRESOLV(shares);
        P2pResolvProxy(localProxy).withdrawRESOLV();
        vm.stopPrank();

        uint256 treasuryAfter = mockResolv.balanceOf(P2pTreasury);
        assertEq(treasuryAfter, treasuryBefore, "no real rewards should mean no fee");
    }

    function test_resolv_withdrawRESOLV_operatorCanCompleteWithdrawal() public {
        deal(RESOLV, clientAddress, 100e18);
        _doDeposit();

        vm.startPrank(clientAddress);
        uint256 sharesBalance = IERC20(stRESOLV).balanceOf(proxyAddress);
        P2pResolvProxy(proxyAddress).initiateWithdrawalRESOLV(sharesBalance);
        vm.stopPrank();

        _forward(14 days);

        uint256 clientBalanceBefore = IERC20(RESOLV).balanceOf(clientAddress);

        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(proxyAddress).withdrawRESOLV();

        uint256 clientBalanceAfter = IERC20(RESOLV).balanceOf(clientAddress);
        assertGt(clientBalanceAfter, clientBalanceBefore, "operator should be able to finalize withdrawal");
    }

    function test_resolv_rewardTokens_getter_matches_deployed_interface() public {
        address firstRewardToken = IResolvStaking(stRESOLV).rewardTokens(0);
        assertEq(firstRewardToken, RESOLV, "unexpected reward token at index 0");

        vm.expectRevert();
        IResolvStaking(stRESOLV).rewardTokens(1);
    }

    function test_resolv_sweepRewardToken_byClient_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 1000e18);
        _doDeposit();

        // Simulate receiving a reward token that's not RESOLV
        address rewardToken = makeAddr("rewardToken");
        uint256 rewardAmount = 100e18;

        // Mock the reward token as an ERC20
        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, proxyAddress),
            abi.encode(rewardAmount)
        );
        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.transfer.selector, clientAddress, rewardAmount),
            abi.encode(true)
        );

        // Expect the transfer and event
        vm.expectCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.transfer.selector, clientAddress, rewardAmount)
        );
        vm.expectEmit(true, false, false, true, proxyAddress);
        emit P2pResolvProxy__RewardTokenSwept(rewardToken, rewardAmount);

        vm.startPrank(clientAddress);
        P2pResolvProxy(proxyAddress).sweepRewardToken(rewardToken);
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    function test_resolv_sweepRewardToken_byP2pOperator_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 1000e18);
        _doDeposit();

        // Simulate receiving a reward token
        address rewardToken = makeAddr("rewardToken");
        uint256 rewardAmount = 50e18;

        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, proxyAddress),
            abi.encode(rewardAmount)
        );
        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.transfer.selector, clientAddress, rewardAmount),
            abi.encode(true)
        );

        vm.expectEmit(true, false, false, true, proxyAddress);
        emit P2pResolvProxy__RewardTokenSwept(rewardToken, rewardAmount);

        vm.startPrank(p2pOperatorAddress);
        P2pResolvProxy(proxyAddress).sweepRewardToken(rewardToken);
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    function test_resolv_sweepRewardToken_cannotSweepProtectedTokens_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 1000e18);
        _doDeposit();

        vm.startPrank(clientAddress);

        // Cannot sweep RESOLV
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__CannotSweepProtectedToken.selector, RESOLV));
        P2pResolvProxy(proxyAddress).sweepRewardToken(RESOLV);

        // Cannot sweep USR
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__CannotSweepProtectedToken.selector, USR));
        P2pResolvProxy(proxyAddress).sweepRewardToken(USR);

        // Cannot sweep stRESOLV
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__CannotSweepProtectedToken.selector, stRESOLV));
        P2pResolvProxy(proxyAddress).sweepRewardToken(stRESOLV);

        // Cannot sweep stUSR
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__CannotSweepProtectedToken.selector, stUSR));
        P2pResolvProxy(proxyAddress).sweepRewardToken(stUSR);

        vm.stopPrank();
    }

    function test_resolv_sweepRewardToken_zeroBalance_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 1000e18);
        _doDeposit();

        address rewardToken = makeAddr("rewardToken");

        // Mock zero balance
        vm.mockCall(
            rewardToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, proxyAddress),
            abi.encode(0)
        );

        // Should not emit event or make transfer call
        vm.startPrank(clientAddress);
        P2pResolvProxy(proxyAddress).sweepRewardToken(rewardToken);
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    function test_resolv_sweepRewardToken_onlyClientOrOperator_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, 1000e18);
        _doDeposit();

        address rewardToken = makeAddr("rewardToken");

        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__CallerNeitherClientNorP2pOperator.selector, nobody));
        P2pResolvProxy(proxyAddress).sweepRewardToken(rewardToken);
        vm.stopPrank();
    }

    function test_resolv_transferP2pSigner_Mainnet_RESOLV() public {
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pSigner(nobody);

        address oldSigner = factory.getP2pSigner();
        assertEq(oldSigner, p2pSignerAddress);

        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pSigner(nobody);

        address newSigner = factory.getP2pSigner();
        assertEq(newSigner, nobody);
    }

    function test_resolv_clientBasisPointsGreaterThan10000_Mainnet_RESOLV() public {
        uint96 invalidBasisPoints = 10001;

        vm.startPrank(clientAddress);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            invalidBasisPoints,
            SigDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__InvalidClientBasisPoints.selector, invalidBasisPoints));
        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            invalidBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_resolv_zeroAddressAsset_Mainnet_RESOLV() public {
        vm.startPrank(clientAddress);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__AssetNotSupported.selector, address(0)));
        factory.deposit(
            referenceProxy,
            address(0),
            0,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_resolv_zeroAssetAmount_Mainnet_RESOLV() public {
        vm.startPrank(clientAddress);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.expectRevert(P2pYieldProxy__ZeroAssetAmount.selector);
        factory.deposit(
            referenceProxy,
            RESOLV,
            0,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_resolv_depositDirectlyOnProxy_Mainnet_RESOLV() public {
        vm.startPrank(clientAddress);

        // Add this line to give initial tokens to the client
        deal(RESOLV, clientAddress, DepositAmount);

        // Add this line to approve tokens for proxyAddress
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);

        // Create proxy first via factory
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        // Now try to call deposit directly on the proxy
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotFactoryCalled.selector,
                clientAddress,
                address(factory)
            )
        );
        P2pResolvProxy(proxyAddress).deposit(
            RESOLV,
            DepositAmount
        );
    }

    function test_resolv_initializeDirectlyOnProxy_Mainnet_RESOLV() public {
        // Create the proxy first since we need a valid proxy address to test with
        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints);
        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);

        vm.startPrank(clientAddress);

        // Add this line to give initial tokens to the client
        deal(RESOLV, clientAddress, DepositAmount);

        // Add this line to approve tokens for Permit2
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        // This will create the proxy
        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        // Now try to initialize it directly
        vm.expectRevert("Initializable: contract is already initialized");
        proxy.initialize(
            clientAddress,
            ClientBasisPoints
        );
        vm.stopPrank();
    }

    function test_resolv_withdrawOnProxyOnlyCallableByClient_Mainnet_RESOLV() public {
        // Create proxy and do initial deposit
        deal(RESOLV, clientAddress, DepositAmount);
        vm.startPrank(clientAddress);
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();

        // Try to withdraw as non-client
        vm.startPrank(nobody);
        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotClientCalled.selector,
                nobody,        // _msgSender (the nobody address trying to call)
                clientAddress  // _actualClient (the actual client address)
            )
        );
        proxy.withdrawAllUSR();
        vm.stopPrank();
    }

    function test_resolv_setStakedTokenDistributor_onlyP2pOperator_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, DepositAmount);
        _doDeposit();

        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);
        address newDistributor = makeAddr("newDistributor");

        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pResolvProxy__NotP2pOperator.selector,
                nobody
            )
        );
        proxy.setStakedTokenDistributor(newDistributor);
        vm.stopPrank();

        vm.startPrank(p2pOperatorAddress);
        vm.expectEmit(true, true, false, true, proxyAddress);
        emit P2pResolvProxy__StakedTokenDistributorUpdated(
            address(0),
            newDistributor
        );
        proxy.setStakedTokenDistributor(newDistributor);
        vm.stopPrank();

        assertEq(proxy.getStakedTokenDistributor(), newDistributor);
    }

    function test_resolv_setStakedTokenDistributor_zeroAddressReverts_Mainnet_RESOLV() public {
        deal(RESOLV, clientAddress, DepositAmount);
        _doDeposit();

        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(P2pResolvProxy__ZeroAddressStakedTokenDistributor.selector);
        P2pResolvProxy(proxyAddress).setStakedTokenDistributor(address(0));
        vm.stopPrank();
    }

    function test_resolv_getP2pLendingProxyFactory__ZeroP2pSignerAddress_Mainnet_RESOLV() public {
        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(P2pYieldProxyFactory__ZeroP2pSignerAddress.selector);
        factory.transferP2pSigner(address(0));
        vm.stopPrank();
    }

    function test_resolv_getHashForP2pSigner_Mainnet_RESOLV() public view {
                bytes32 expectedHash = keccak256(abi.encode(
            referenceProxy,
            clientAddress,
            ClientBasisPoints,
            SigDeadline,
            address(factory),
            block.chainid
        ));

        bytes32 actualHash = factory.getHashForP2pSigner(
            referenceProxy,
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        assertEq(actualHash, expectedHash);
    }

    function test_resolv_supportsInterface_Mainnet_RESOLV() public view {
        // Test IP2pLendingProxyFactory interface support
        bool supportsP2pLendingProxyFactory = factory.supportsInterface(type(IP2pYieldProxyFactory).interfaceId);
        assertTrue(supportsP2pLendingProxyFactory);

        // Test IERC165 interface support
        bool supportsERC165 = factory.supportsInterface(type(IERC165).interfaceId);
        assertTrue(supportsERC165);

        // Test non-supported interface
        bytes4 nonSupportedInterfaceId = bytes4(keccak256("nonSupportedInterface()"));
        bool supportsNonSupported = factory.supportsInterface(nonSupportedInterfaceId);
        assertFalse(supportsNonSupported);
    }

    function test_resolv_p2pSignerSignatureExpired_Mainnet_RESOLV() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(RESOLV, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);

        // Get p2p signer signature with expired deadline
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            expiredDeadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxyFactory__P2pSignerSignatureExpired.selector,
                expiredDeadline
            )
        );

        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            expiredDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_resolv_invalidP2pSignerSignature_Mainnet_RESOLV() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(RESOLV, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);

        // Create an invalid signature by using a different private key
        uint256 wrongPrivateKey = 0x12345; // Some random private key
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(
            factory.getHashForP2pSigner(
            referenceProxy,
            clientAddress,
                ClientBasisPoints,
                SigDeadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, messageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);

        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            invalidSignature
        );
        vm.stopPrank();
    }

    function test_resolv_viewFunctions_Mainnet_RESOLV() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(RESOLV, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);

        // Add this line to approve tokens for Permit2
        IERC20(RESOLV).safeApprove(proxyAddress, DepositAmount);

        // Create proxy first via factory
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);
        assertEq(proxy.getFactory(), address(factory));
        assertEq(proxy.getP2pTreasury(), P2pTreasury);
        assertEq(proxy.getClient(), clientAddress);
        assertEq(proxy.getClientBasisPoints(), ClientBasisPoints);
        assertEq(proxy.getStakedTokenDistributor(), address(0));
        assertEq(factory.getP2pSigner(), p2pSignerAddress);
        assertEq(factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints), proxyAddress);
    }

    function test_resolv_acceptP2pOperator_Mainnet_RESOLV() public {
        // Initial state check
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);

        // Only operator can initiate transfer
        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                nobody
            )
        );
        factory.transferP2pOperator(nobody);
        vm.stopPrank();

        // Operator initiates transfer
        address newOperator = makeAddr("newOperator");
        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pOperator(newOperator);

        // Check pending operator is set
        assertEq(factory.getPendingP2pOperator(), newOperator);
        // Check current operator hasn't changed yet
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);
        vm.stopPrank();

        // Wrong address cannot accept transfer
        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                nobody
            )
        );
        factory.acceptP2pOperator();
        vm.stopPrank();

        // New operator accepts transfer
        vm.startPrank(newOperator);
        factory.acceptP2pOperator();

        // Check operator was updated
        assertEq(factory.getP2pOperator(), newOperator);
        // Check pending operator was cleared
        assertEq(factory.getPendingP2pOperator(), address(0));
        vm.stopPrank();

        // Old operator can no longer call operator functions
        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                p2pOperatorAddress
            )
        );
        factory.transferP2pOperator(p2pOperatorAddress);
        vm.stopPrank();
    }

    function test_resolv_DropClaim() public {
        deal(RESOLV, clientAddress, 10000e18);
        _doDeposit();

        vm.prank(p2pOperatorAddress);
        P2pResolvProxy(proxyAddress).setStakedTokenDistributor(StakedTokenDistributor);

        bytes memory deployedCode = proxyAddress.code;
        address target = 0xa02A67966Ef2BFf32A225374EC71fDF7B2a6f9Ae;
        vm.etch(target, deployedCode);
        P2pResolvProxy instance = P2pResolvProxy(target);

        vm.prank(p2pOperatorAddress);
        instance.setStakedTokenDistributor(StakedTokenDistributor);

        bytes32[] memory proof = new bytes32[](16);
        proof[0]  = 0x4ede751b1890af45c32c8d933e09d283734f3d5b81fb3eeb32dd95dea4e84aff;
        proof[1]  = 0x23e277927c5c54060c57b9af069dfa8fc86f55a0314e2b4ef3f7015d3c62269e;
        proof[2]  = 0xa94ce2924dd66f78f1c6f77d9bd4a067b2cb6709e26fdc8d132e87bfa7896fa9;
        proof[3]  = 0xe06247541b3d9663431c4650196b3f7c310400b24163cd58ecf6230c8326dce6;
        proof[4]  = 0x6a5b617cfdf0392b62f12ee976f0697d9eb7ea5d1ac5fb414c1d6fe73c2f023b;
        proof[5]  = 0x81fac1df105e716a549a51fc82b9ca9c44a4c6522635985c680ba3f458a06d40;
        proof[6]  = 0xd787f718d5a67bd8f0e7b34ed182ea2066ae5b60cac0cbabce713ad615e9b68f;
        proof[7]  = 0x04b693a779b2727cce62245a550b952833b04dfe73ed6d4a8f838fdfcf19850e;
        proof[8]  = 0xf050e0102b36a462b4e99a689ef4e49870cdb8d0a03c71c9553e0a2db7f9bc7f;
        proof[9]  = 0xe8a0cbb6373c030dd89d02e41d54267bb5d0d5850fcbd79b1c1ba1a12db8ef48;
        proof[10] = 0xae6ee1cd3f80bd44c7c122b5a227b95435db1211674f02c103ee72f760f534d8;
        proof[11] = 0xcd62f71686005a2780c1c4221de6b370493c4a119801bc8a28a6fead913db4a0;
        proof[12] = 0x3773a86db35b2397b2f1a550bee7c441f121aabed9faa743678eb3c349d25c82;
        proof[13] = 0x80d33b49260c94312d911d0cb054e27a7578e745535edbfd8afe0e5eab2c2534;
        proof[14] = 0xb0a1a05f9b216a04e42bb1a555177275eeb915f61075ccc5d1731b97d6e68fad;
        proof[15] = 0x6da159156088ae144937d1f0aa044231361fe9f24dbe3edfa5dca69c99e451d4;

        vm.startPrank(p2pOperatorAddress);
        instance.claimStakedTokenDistributor(
            2801,
            2616282100000000000000,
            proof
        );
        vm.stopPrank();
    }

    function _getP2pSignerSignature(
        address _clientAddress,
        uint96 _clientBasisPoints,
        uint256 _sigDeadline
    ) private view returns(bytes memory) {
        // p2p signer signing
        bytes32 hashForP2pSigner = factory.getHashForP2pSigner(
            referenceProxy,
            _clientAddress,
            _clientBasisPoints,
            _sigDeadline
        );
        bytes32 ethSignedMessageHashForP2pSigner = ECDSA.toEthSignedMessageHash(hashForP2pSigner);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(p2pSignerPrivateKey, ethSignedMessageHashForP2pSigner);
        bytes memory p2pSignerSignature = abi.encodePacked(r2, s2, v2);
        return p2pSignerSignature;
    }

    function _doDeposit() private {
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        if (IERC20(RESOLV).allowance(clientAddress, proxyAddress) == 0) {
            IERC20(RESOLV).safeApprove(proxyAddress, type(uint256).max);
        }
        factory.deposit(
            referenceProxy,
            RESOLV,
            DepositAmount,

            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function _doWithdraw(uint256 denominator) private returns (uint256 withdrawnAmount) {
        uint256 sharesBalance = IERC20(stRESOLV).balanceOf(proxyAddress);
        uint256 sharesToWithdraw = sharesBalance / denominator;

        uint256 clientBalanceBefore = IERC20(RESOLV).balanceOf(clientAddress);

        vm.startPrank(clientAddress);
        P2pResolvProxy(proxyAddress).initiateWithdrawalRESOLV(sharesToWithdraw);

        _forward(10_000 * 14);

        P2pResolvProxy(proxyAddress).withdrawRESOLV();
        vm.stopPrank();

        uint256 clientBalanceAfter = IERC20(RESOLV).balanceOf(clientAddress);
        return clientBalanceAfter - clientBalanceBefore;
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 13);
    }

    function _setupMockResolvEnvironment(uint256 depositAmount)
    private
    returns (address proxyAddr, MockERC20 mockResolv, MockResolvStaking mockStResolv)
    {
        AllowedCalldataChecker checker = new AllowedCalldataChecker();
        checker.initialize();
        AllowedCalldataChecker clientToP2pChecker = new AllowedCalldataChecker();
        clientToP2pChecker.initialize();

        mockResolv = new MockERC20("RESOLV", "RESOLV");
        MockERC20 mockUsr = new MockERC20("USR", "USR");
        MockStUSR mockStUsr = new MockStUSR(mockUsr);
        mockStResolv = new MockResolvStaking(mockResolv);

        vm.startPrank(p2pOperatorAddress);
        factory = new P2pYieldProxyFactory(p2pSignerAddress);
        referenceProxy = address(
            new P2pResolvProxy(
                address(factory),
                P2pTreasury,
                address(checker),
                address(clientToP2pChecker),
                address(mockStUsr),
                address(mockUsr),
                address(mockStResolv),
                address(mockResolv)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddr = factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints);

        mockResolv.mint(clientAddress, depositAmount);
        bytes memory signature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        mockResolv.approve(proxyAddr, depositAmount);
        factory.deposit(
            referenceProxy,
            address(mockResolv),
            depositAmount,
            ClientBasisPoints,
            SigDeadline,
            signature
        );
        vm.stopPrank();
    }
}

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        if (currentAllowance != type(uint256).max) {
            allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(from != address(0), "ERC20: transfer from the zero address");
        uint256 fromBalance = balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            balances[from] = fromBalance - amount;
        }
        balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 fromBalance = balances[from];
        require(fromBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            balances[from] = fromBalance - amount;
        }
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

contract MockStUSR is MockERC20, IStUSR {
    MockERC20 public immutable usr;

    constructor(MockERC20 _usr) MockERC20("Mock stUSR", "mstUSR") {
        usr = _usr;
    }

    function deposit(uint256 _usrAmount) external override {
        if (_usrAmount == 0) {
            revert InvalidDepositAmount(_usrAmount);
        }
        usr.transferFrom(msg.sender, address(this), _usrAmount);
        _mint(msg.sender, _usrAmount);
        emit Deposit(msg.sender, msg.sender, _usrAmount, _usrAmount);
    }

    function withdraw(uint256 _usrAmount) external override {
        _burn(msg.sender, _usrAmount);
        usr.transfer(msg.sender, _usrAmount);
        emit Withdraw(msg.sender, msg.sender, _usrAmount, _usrAmount);
    }

    function withdrawAll() external override {
        this.withdraw(balanceOf(msg.sender));
    }

    function previewDeposit(uint256 _usrAmount) external pure override returns (uint256 shares) {
        return _usrAmount;
    }

    function previewWithdraw(uint256 _usrAmount) external pure override returns (uint256 shares) {
        return _usrAmount;
    }
}

contract MockResolvStaking is MockERC20, IResolvStaking {
    MockERC20 public immutable resolv;

    bool private claimRewardsEnabled = true;

    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256) public claimableRewards;
    mapping(address => uint256) public checkpointRewards;
    mapping(address => uint256) public overrideEffectiveBalance;
    address[] private rewardTokenList;
    mapping(address token => mapping(address user => uint256 amount)) public tokenRewardAmounts;

    constructor(MockERC20 _resolv) MockERC20("Mock stRESOLV", "mstRESOLV") {
        resolv = _resolv;
    }

    function deposit(
        uint256 _amount,
        address _receiver
    ) external override {
        resolv.transferFrom(msg.sender, address(this), _amount);
        _mint(_receiver, _amount);
    }

    function withdraw(
        bool _claimRewards,
        address _receiver
    ) external override {
        uint256 pending = pendingWithdrawals[msg.sender];
        pendingWithdrawals[msg.sender] = 0;
        if (pending > 0) {
            resolv.transfer(_receiver, pending);
        }

        if (_claimRewards) {
            uint256 rewards = claimableRewards[msg.sender] + checkpointRewards[msg.sender];
            if (rewards > 0) {
                claimableRewards[msg.sender] = 0;
                checkpointRewards[msg.sender] = 0;
                resolv.mint(_receiver, rewards);
            }
        }
    }

    function initiateWithdrawal(uint256 _amount) external override {
        pendingWithdrawals[msg.sender] += _amount;
        _burn(msg.sender, _amount);
    }

    function claim(address _user, address _receiver) external override {
        uint256 rewards = claimableRewards[_user];
        claimableRewards[_user] = 0;
        if (rewards > 0) {
            resolv.mint(_receiver, rewards);
        }

        for (uint256 i; i < rewardTokenList.length; ++i) {
            address tokenAddr = rewardTokenList[i];
            uint256 tokenReward = tokenRewardAmounts[tokenAddr][_user];
            if (tokenReward > 0) {
                tokenRewardAmounts[tokenAddr][_user] = 0;
                if (tokenAddr == address(resolv)) {
                    resolv.mint(_receiver, tokenReward);
                } else {
                    MockERC20(tokenAddr).mint(_receiver, tokenReward);
                }
            }
        }
    }

    function updateCheckpoint(address _user) external override {
        uint256 rewards = checkpointRewards[_user];
        if (rewards > 0) {
            checkpointRewards[_user] = 0;
            claimableRewards[_user] += rewards;
        }
    }

    function depositReward(
        address,
        uint256 _amount,
        uint256
    ) external override {
        resolv.mint(address(this), _amount);
    }

    function setRewardsReceiver(address) external override {}

    function setCheckpointDelegatee(address) external override {}

    function setClaimEnabled(bool _enabled) external override {
        claimRewardsEnabled = _enabled;
    }

    function setWithdrawalCooldown(uint256) external override {}

    function getUserAccumulatedRewardPerToken(address _user, address) external view override returns (uint256 amount) {
        return claimableRewards[_user] + checkpointRewards[_user];
    }

    function getUserClaimableAmounts(address _user, address) external view override returns (uint256 amount) {
        return claimableRewards[_user];
    }

    function getUserEffectiveBalance(address _user) external view override returns (uint256 balance) {
        uint256 custom = overrideEffectiveBalance[_user];
        if (custom > 0) {
            return custom;
        }
        return balanceOf(_user);
    }

    function claimEnabled() external view override returns (bool isEnabled) {
        return claimRewardsEnabled;
    }

    function rewardTokens(uint256 _index) external view override returns (address token) {
        require(_index < rewardTokenList.length, "reward token oob");
        return rewardTokenList[_index];
    }

    // ----------------------
    // Helpers for test setup
    // ----------------------
    function setCheckpointRewards(address _user, uint256 _amount) external {
        checkpointRewards[_user] = _amount;
    }

    function setClaimableRewards(address _user, uint256 _amount) external {
        claimableRewards[_user] = _amount;
    }

    function setOverrideEffectiveBalance(address _user, uint256 _amount) external {
        overrideEffectiveBalance[_user] = _amount;
    }

    function addRewardToken(address _token) external {
        rewardTokenList.push(_token);
    }

    function setRewardTokenAmount(address _token, address _user, uint256 _amount) external {
        tokenRewardAmounts[_token][_user] = _amount;
    }
}

contract MockStakedTokenDistributor is IStakedTokenDistributor {
    MockERC20 public immutable token;
    IResolvStaking public immutable staking;

    mapping(uint256 => bool) public claimed;

    constructor(MockERC20 _token, IResolvStaking _staking) {
        token = _token;
        staking = _staking;
        _token.approve(address(_staking), type(uint256).max);
    }

    function claim(uint256 _index, uint256 _amount, bytes32[] calldata) external override {
        require(!claimed[_index], "already claimed");
        claimed[_index] = true;
        token.mint(address(this), _amount);
        staking.deposit(_amount, msg.sender);
        emit Claimed(_index, msg.sender, _amount);
    }

    function isClaimed(uint256 _index) external view override returns (bool) {
        return claimed[_index];
    }
}
