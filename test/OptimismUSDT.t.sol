// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/access/P2pOperator.sol";
import "../src/adapters/superform/p2pSuperformProxyFactory/P2pSuperformProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "./utils/merkle/helper/MerkleReader.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import {PermitHash} from "../src/@permit2/libraries/PermitHash.sol";


contract OptimismUSDT is Test, MerkleReader {
    using SafeERC20 for IERC20;

    address constant USDT = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address constant SuperformRouter = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address constant SuperPositions = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address constant RewardsDistributorInstance = 0xce23bD7205bF2B543F6B4eeC00Add0C111FEFc3B;

    address constant RewardsDistributorAdmin = 0xf82F3D7Df94FC2994315c32322DA6238cA2A2f7f;

    address constant P2pTreasury = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;

    uint256 constant SuperformId = 62771017356190754913478451444852273738203985736479809223259;

    P2pSuperformProxyFactory private factory;

    address private clientAddress;
    uint256 private clientPrivateKey;

    address private p2pSignerAddress;
    uint256 private p2pSignerPrivateKey;

    address private p2pOperatorAddress;
    address private nobody;

    uint256 constant SigDeadline = 1789558996;
    uint48 constant ClientBasisPointsOfProfit = 8700; // 13% fee
    uint48 constant ClientBasisPointsOfDeposit = 10_000; // 0% fee
    uint256 constant DepositAmount = 124071208818789728;
    uint256 constant SharesAmount = 124071208818789728;

    address proxyAddress;

    uint48 nonce;

    uint64 public constant CHAIN_ID = 10;

    uint256 totalUSDCToDeposit;
    uint256 totalDAIToDeposit;

    function setUp() public {
        vm.createSelectFork("optimism", 133700000);

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
        factory = new P2pSuperformProxyFactory(
            p2pSignerAddress,
            P2pTreasury,
            SuperformRouter,
            SuperPositions,
            address(tup),
            RewardsDistributorInstance
        );
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit
        );

        deal(USDT, clientAddress, 10000e18);
    }

    function test_happyPath_Optimism() public {
        _doDeposit();
        _doWithdraw();
    }

    function test_P2pOperator2Step() public {
        // Get initial P2pOperator
        address initialP2pOperator = factory.getP2pOperator();
        assertEq(initialP2pOperator, p2pOperatorAddress);

        // Create new P2pOperator address
        address newP2pOperator = makeAddr("newP2pOperator");

        // Step 1: Current P2pOperator initiates transfer
        vm.prank(p2pOperatorAddress);
        factory.transferP2pOperator(newP2pOperator);

        // Verify pending P2pOperator is set
        assertEq(factory.getPendingP2pOperator(), newP2pOperator);
        // Verify current P2pOperator hasn't changed yet
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);

        // Step 2: New P2pOperator accepts transfer
        vm.prank(newP2pOperator);
        factory.acceptP2pOperator();

        // Verify P2pOperator was updated
        assertEq(factory.getP2pOperator(), newP2pOperator);
        // Verify pending P2pOperator was cleared
        assertEq(factory.getPendingP2pOperator(), address(0));
    }

    function testP2pSuperformProxy__LiqRequestTokenShouldBeEqualToPermitForP2pYieldProxyToken() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
            token: address(0x1234), // Different token than in liqRequest
            amount: uint160(DepositAmount),
            expiration: uint48(block.timestamp + 1 days),
            nonce: 0
        }),
            spender: address(factory),
            sigDeadline: SigDeadline
        });
        bytes memory permit2SignatureForP2pYieldProxy = _getPermit2SignatureForP2pYieldProxy(permitSingleForP2pYieldProxy);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        if (IERC20(USDT).allowance(clientAddress, address(Permit2Lib.PERMIT2)) == 0) {
            IERC20(USDT).safeApprove(address(Permit2Lib.PERMIT2), type(uint256).max);
        }

        LiqRequest memory liqRequest = LiqRequest({
            txData: hex'4630a0d896ba9cffae8a22aa75ffdc6910e52d52ee9a199ee31eb8893dc693d7c89ed4a800000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000097116661c85c4e1ee35aa10f7fc5fe5e67b83a5b00000000000000000000000000000000000000000000000001a2c000701289810000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a30783030303030303030303030303030303030303030303030303030303030303030303030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc0000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc00000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b2819000000000000000000000000000000000000000000000000000000000001e20800000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001842646478b00000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000000000000000000000000000000000000001e208000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b281900000000000000000000000000000000000000000000000001a2c000701289810000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000840294b008aa00579c1307b0ef2c499ad98a8ce58e5801ffff01962e23cd3f58f887a5238082a75d223f71890629006140b987d6b51fd75b66c3b07733beb5167c42fc010b2c639c533813f4aa9d7837caf62653d097ff8501ffff018ac2f9dac7a2852d44f3c09634444d533e4c078e011231deb6f5749ef6ce6943a275a1d3e7486f4eae0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
            token: USDT,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: DepositAmount,
            outputAmount: SharesAmount,
            maxSlippage: 500,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: proxyAddress,
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        vm.expectRevert(abi.encodeWithSelector(
            P2pSuperformProxy__LiqRequestTokenShouldBeEqualToPermitForP2pYieldProxyToken.selector,
            USDT,
            address(0x1234)
        ));
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

            superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_P2pYieldProxyFactory__InvalidP2pSignerSignature() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature;
        bytes memory superformCalldata = new bytes(3); // Less than 4 bytes for function selector

        vm.startPrank(clientAddress);
        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

            superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_P2pYieldProxy__EmergencyTokenWithdraw() public {
        _doDeposit();
        
        // Deal USDT to the proxy
        uint256 usdtAmount = 1000 * 10**6; // 1000 USDT with 6 decimals
        deal(USDT, proxyAddress, usdtAmount);
        
        // Verify initial balances
        assertEq(IERC20(USDT).balanceOf(proxyAddress), usdtAmount);
        uint256 clientInitialBalance = IERC20(USDT).balanceOf(clientAddress);

        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, address(this), clientAddress));
        P2pYieldProxy(payable(proxyAddress)).emergencyTokenWithdraw(USDT);
        
        // Call emergencyTokenWithdraw as client
        vm.startPrank(clientAddress);
        P2pYieldProxy(payable(proxyAddress)).emergencyTokenWithdraw(USDT);
        vm.stopPrank();
        
        // Verify final balances
        assertEq(IERC20(USDT).balanceOf(proxyAddress), 0);
        assertEq(IERC20(USDT).balanceOf(clientAddress) - clientInitialBalance, usdtAmount);
    }

    function test_P2pSuperformProxy__SuperformCalldataTooShort() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );
        bytes memory superformCalldata = new bytes(3); // Less than 4 bytes for function selector

        vm.startPrank(clientAddress);
        vm.expectRevert(P2pSuperformProxy__SuperformCalldataTooShort.selector);
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

            superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_P2pSuperformProxy__SelectorNotSupported() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );
        
        // Create calldata with an unsupported selector
        bytes4 unsupportedSelector = bytes4(keccak256("unsupportedFunction()"));
        bytes memory superformCalldata = abi.encodePacked(unsupportedSelector, "42");

        vm.startPrank(clientAddress);
        vm.expectRevert(abi.encodeWithSelector(P2pSuperformProxy__SelectorNotSupported.selector, unsupportedSelector));
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

            superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_batchclaim_proxy() public {
        _doDeposit();

        _addRoot();
        _addRoot24();

        // common user
        address user = proxyAddress;

        uint256[] memory periodIds = new uint256[](2);
        periodIds[0] = 23;
        periodIds[1] = 24;

        bytes32[][] memory proofs = new bytes32[][](2);

        address[][] memory tokensToClaim = new address[][](2);

        uint256[][] memory amountsToClaim = new uint256[][](2);
        for (uint256 periodId = 0; periodId < 2; periodId++) {
            (,,,, bytes32[] memory proof_, address[] memory tokensToClaim_, uint256[] memory amountsToClaim_) =
                            _generateMerkleTree(MerkleReader.MerkleArgs(periodId + 23, user, CHAIN_ID));

            proofs[periodId] = proof_;
            tokensToClaim[periodId] = tokensToClaim_;
            amountsToClaim[periodId] = amountsToClaim_;
        }

        vm.prank(clientAddress);
        IP2pSuperformProxy(payable(proxyAddress)).batchClaim(
            periodIds,
            tokensToClaim,
            amountsToClaim,
            proofs
        );
    }

    function test_batchclaim_randomClaimer_claimAndAlreadyClaimed() public {
        _addRoot();
        _addRoot24();

        // common user
        address user = proxyAddress;

        uint256[] memory periodIds = new uint256[](2);
        periodIds[0] = 23;
        periodIds[1] = 24;

        bytes32[][] memory proofs = new bytes32[][](2);

        address[][] memory tokensToClaim = new address[][](2);

        uint256[][] memory amountsToClaim = new uint256[][](2);
        for (uint256 periodId = 0; periodId < 2; periodId++) {
            (,,,, bytes32[] memory proof_, address[] memory tokensToClaim_, uint256[] memory amountsToClaim_) =
                            _generateMerkleTree(MerkleReader.MerkleArgs(periodId + 23, user, CHAIN_ID));

            proofs[periodId] = proof_;
            tokensToClaim[periodId] = tokensToClaim_;
            amountsToClaim[periodId] = amountsToClaim_;
        }

        /// @dev tests a claim initiated by a random user on behalf of user
        vm.prank(address(0x777));
        IRewardsDistributor(RewardsDistributorInstance).batchClaim(user, periodIds, tokensToClaim, amountsToClaim, proofs);

        vm.expectRevert(IRewardsDistributor.ALREADY_CLAIMED.selector);
        vm.prank(user);
        IRewardsDistributor(RewardsDistributorInstance).batchClaim(user, periodIds, tokensToClaim, amountsToClaim, proofs);
    }

    function _addRoot() internal {
        bytes32 root;
        uint256 usdcToDeposit;
        uint256 daiToDeposit;
        uint256 periodId = 23; // IRewardsDistributor(RewardsDistributorInstance).currentPeriodId();
        (root,, usdcToDeposit, daiToDeposit,,,) = _generateMerkleTree(MerkleReader.MerkleArgs(periodId, proxyAddress, CHAIN_ID));

        vm.startPrank(RewardsDistributorAdmin);
        IRewardsDistributor(RewardsDistributorInstance).setPeriodicRewards(root);
        totalUSDCToDeposit += usdcToDeposit;
        totalDAIToDeposit += daiToDeposit;

        deal(USDC, RewardsDistributorInstance, totalUSDCToDeposit);
        deal(DAI, RewardsDistributorInstance, totalDAIToDeposit);
        vm.stopPrank();
    }

    function _addRoot24() internal {
        bytes32 root;
        uint256 usdcToDeposit;
        uint256 daiToDeposit;
        (root,, usdcToDeposit, daiToDeposit,,,) = _generateMerkleTree(MerkleReader.MerkleArgs(24, proxyAddress, CHAIN_ID));

        vm.startPrank(RewardsDistributorAdmin);
        IRewardsDistributor(RewardsDistributorInstance).setPeriodicRewards(root);
        totalUSDCToDeposit += usdcToDeposit;
        totalDAIToDeposit += daiToDeposit;

        deal(USDC, RewardsDistributorInstance, totalUSDCToDeposit);
        deal(DAI, RewardsDistributorInstance, totalDAIToDeposit);
        vm.stopPrank();
    }

    function _getVaultAddress() private pure returns(address) {
        return address(uint160(SuperformId));
    }

    function _getPermitSingleForP2pYieldProxy() private returns(IAllowanceTransfer.PermitSingle memory) {
        IAllowanceTransfer.PermitDetails memory permitDetails = IAllowanceTransfer.PermitDetails({
            token: USDT,
            amount: uint160(DepositAmount),
            expiration: uint48(SigDeadline),
            nonce: nonce
        });
        nonce++;

        // data for factory
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy = IAllowanceTransfer.PermitSingle({
            details: permitDetails,
            spender: proxyAddress,
            sigDeadline: SigDeadline
        });

        return permitSingleForP2pYieldProxy;
    }

    function _getPermit2SignatureForP2pYieldProxy(IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy) private view returns(bytes memory) {
        bytes32 permitSingleForP2pYieldProxyHash = factory.getPermit2HashTypedData(PermitHash.hash(permitSingleForP2pYieldProxy));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(clientPrivateKey, permitSingleForP2pYieldProxyHash);
        bytes memory permit2SignatureForP2pYieldProxy = abi.encodePacked(r1, s1, v1);
        return permit2SignatureForP2pYieldProxy;
    }

    function _getP2pSignerSignature(
        address _clientAddress,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _sigDeadline
    ) private view returns(bytes memory) {
        // p2p signer signing
        bytes32 hashForP2pSigner = factory.getHashForP2pSigner(
            _clientAddress,
            _clientBasisPointsOfDeposit,
            _clientBasisPointsOfProfit,
            _sigDeadline
        );
        bytes32 ethSignedMessageHashForP2pSigner = ECDSA.toEthSignedMessageHash(hashForP2pSigner);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(p2pSignerPrivateKey, ethSignedMessageHashForP2pSigner);
        bytes memory p2pSignerSignature = abi.encodePacked(r2, s2, v2);
        return p2pSignerSignature;
    }

    function _doDeposit() private {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy = _getPermitSingleForP2pYieldProxy();
        bytes memory permit2SignatureForP2pYieldProxy = _getPermit2SignatureForP2pYieldProxy(permitSingleForP2pYieldProxy);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        if (IERC20(USDT).allowance(clientAddress, address(Permit2Lib.PERMIT2)) == 0) {
            IERC20(USDT).safeApprove(address(Permit2Lib.PERMIT2), type(uint256).max);
        }

        LiqRequest memory liqRequest = LiqRequest({
            txData: hex'4630a0d896ba9cffae8a22aa75ffdc6910e52d52ee9a199ee31eb8893dc693d7c89ed4a800000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000097116661c85c4e1ee35aa10f7fc5fe5e67b83a5b00000000000000000000000000000000000000000000000001a2c000701289810000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a30783030303030303030303030303030303030303030303030303030303030303030303030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc0000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc00000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b2819000000000000000000000000000000000000000000000000000000000001e20800000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001842646478b00000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000000000000000000000000000000000000001e208000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b281900000000000000000000000000000000000000000000000001a2c000701289810000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000840294b008aa00579c1307b0ef2c499ad98a8ce58e5801ffff01962e23cd3f58f887a5238082a75d223f71890629006140b987d6b51fd75b66c3b07733beb5167c42fc010b2c639c533813f4aa9d7837caf62653d097ff8501ffff018ac2f9dac7a2852d44f3c09634444d533e4c078e011231deb6f5749ef6ce6943a275a1d3e7486f4eae0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
            token: USDT,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: DepositAmount,
            outputAmount: SharesAmount,
            maxSlippage: 500,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: proxyAddress,
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));
        
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

        superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function _doWithdraw() private {
        LiqRequest memory liqRequest = LiqRequest({
            txData: hex'4630a0d8db58392a5ec14b23ef56401c814f1ce0bff3fd4f7f74c06e092670b4c587c7a600000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000fd35454f266dc9f672985260029f1686c6b6036c000000000000000000000000000000000000000000000000000000000000181a0000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a30783030303030303030303030303030303030303030303030303030303030303030303030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc0000000000000000000000006140b987d6b51fd75b66c3b07733beb5167c42fc000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b281900000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000000000000000000000000000002c14939f0666fb00000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001442646478b000000000000000000000000c40f949f8a4e094d1b49a23ea9241d289b7b2819000000000000000000000000000000000000000000000000002c14939f0666fb00000000000000000000000094b008aa00579c1307b0ef2c499ad98a8ce58e58000000000000000000000000000000000000000000000000000000000000181a0000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae00000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000004202c40f949f8a4e094d1b49a23ea9241d289b7b281901ffff01e8a05463f7a2796e1bf11a25d317f17ed7fce5e7001231deb6f5749ef6ce6943a275a1d3e7486f4eae00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
            token: USDT,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: 12407523236013819,
            outputAmount: 12407523236013819,
            maxSlippage: 5000,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: proxyAddress,
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });
        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultWithdraw, (req));

        vm.startPrank(clientAddress);
        P2pSuperformProxy(payable(proxyAddress)).withdraw(superformCalldata);
        vm.stopPrank();
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 13);
    }
}