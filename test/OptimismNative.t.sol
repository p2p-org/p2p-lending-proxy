// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/access/P2pOperator.sol";
import "../src/access/P2pOperator.sol";
import "../src/adapters/superform/p2pSuperformProxyFactory/P2pSuperformProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "./mocks/MockAllowedCalldataChecker.sol";
import "./utils/Error.sol";
import "./utils/merkle/helper/MerkleReader.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import {PermitHash} from "../src/@permit2/libraries/PermitHash.sol";


contract OptimismNative is Test, MerkleReader {
    using SafeERC20 for IERC20;

    address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant SuperformRouter = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address constant SuperPositions = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address constant RewardsDistributorInstance = 0xce23bD7205bF2B543F6B4eeC00Add0C111FEFc3B;

    address constant RewardsDistributorAdmin = 0xf82F3D7Df94FC2994315c32322DA6238cA2A2f7f;

    address constant P2pTreasury = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;

    uint256 constant SuperformId = 62771017356379199835532377802369906037722899472923496568460;

    bytes constant LiqRequestTxSata = hex'4630a0d8dac814cc41f28f3f61b1c75cf080011e2f868b0037392f8ae14f7b42bae3be4a00000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000b8138fff124dd7f91abf412b73be453fb140568c0000000000000000000000000000000000000000000000000022bd6ab3cf83760000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a30783030303030303030303030303030303030303030303030303030303030303030303030303030303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b50000000000000000000000006131b5fae19ea4f9d964eac0408e4408b66337b500000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f32b1c2345538c0c6f582fcb022739c4a194ebb000000000000000000000000000000000000000000000000002bd72a2487400000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000664e21fd0e90000000000000000000000000000000000000000000000000000000000000020000000000000000000000000c7d3ab410d49b664d03fe5b1038852ac852b1b29000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000003c000000000000000000000000000000000000000000000000000000000000000f3010100000048000000ba12222222228d8ba445958a75a0704d566bf2c87ca75bdea9dede97f8b13c6641b768650cb837820002000000000000000000d5000000000000000000002bd72a248740000beeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1f32b1c2345538c0c6f582fcb022739c4a194ebb1231deb6f5749ef6ce6943a275a1d3e7486f4eae000000000000000000000000680a01200000005400000000000000000000000000000000000000000000000000000000000000000000000000000000000000026583c34c00000000000000000024917dcabf7ce84f82e73edb06d29ff62c91ec8f5ff06571bdeb2900000000000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000001f32b1c2345538c0c6f582fcb022739c4a194ebb0000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae000000000000000000000000000000000000000000000000002bd72a248740000000000000000000000000000000000000000000000000000022bd6ab3cf8376000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000025d7b22536f75726365223a226c692e6669222c22416d6f756e74496e555344223a2232312e3339343431353230343638313437222c22416d6f756e744f7574555344223a2232312e333934363835343533303031343635222c22526566657272616c223a22222c22466c616773223a302c22416d6f756e744f7574223a223130323933303638363230303730313230222c2254696d657374616d70223a313734353438343931322c22526f7574654944223a2238626338353330632d376465312d343437302d393631622d363734666431616662663337222c22496e74656772697479496e666f223a7b224b65794944223a2231222c225369676e6174757265223a2258424a3749307656656b7368513459435953343971574345494e53793755696f304e6249706d556f574945506c743335616b55734c394a3333777857506956794d37685357545470642b62627a56574a394d67694a32346a4e43324861767463766a4a77716145554b723757474b5448387835747134304743362f7478374735594635487a664a49342f66456c353657474a39327635304d664d4b31527366516d326a43444a7849656d376e71484a4644684f43686b6e67394433454d6f6b686d3030696675637a6158574f444d722f346464396e656e58336869364847775a51412b754667557a77387331526373646570725a3557656958705033572b41596a6a394b5a794a4a627346424768524c6768516f3238486843314c3373412f6842346e347a59374669566d6967534a614b4c325475734535677450484935684d6d66764d2f4876437858797a4c413359666b734678413d3d227d7d00000000000000000000000000000000000000000000000000000000000000';

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
    uint256 constant DepositAmount = 12340000000000000;
    uint256 constant VaultAmount = 10293068620070120;
    uint256 constant VaultOutputAmount = 10284585609330856;

    address proxyAddress;

    uint48 nonce;

    uint64 public constant CHAIN_ID = 10;

    uint256 totalUSDCToDeposit;
    uint256 totalDAIToDeposit;

    ProxyAdmin private admin;
    TransparentUpgradeableProxy private tup;

    function setUp() public {
        vm.createSelectFork("optimism", 134943023);

        (clientAddress, clientPrivateKey) = makeAddrAndKey("client");
        (p2pSignerAddress, p2pSignerPrivateKey) = makeAddrAndKey("p2pSigner");
        p2pOperatorAddress = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperatorAddress);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        tup = new TransparentUpgradeableProxy(
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

        deal(clientAddress, 10000e18);
    }

    function test_happyPath_native_Optimism() public {
        _doDeposit();
        _doWithdraw();
    }

    function test_P2pYieldProxy__EmergencyTokenWithdraw() public {
        _doDeposit();

        // Deal USDT to the proxy
        uint256 ethAmount = 1000 ether; // 1000 ETH
        deal(proxyAddress, ethAmount);

        // Verify initial balances
        assertEq(proxyAddress.balance, ethAmount);
        uint256 clientInitialBalance = clientAddress.balance;

        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotClientCalled.selector, address(this), clientAddress));
        P2pYieldProxy(payable(proxyAddress)).emergencyNativeWithdraw();

        // Call emergencyTokenWithdraw as client
        vm.startPrank(clientAddress);
        P2pYieldProxy(payable(proxyAddress)).emergencyNativeWithdraw();
        vm.stopPrank();

        // Verify final balances
        assertEq(proxyAddress.balance, 0);
        assertEq(clientAddress.balance - clientInitialBalance, ethAmount);
    }

    function test_P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);

        LiqRequest memory liqRequest = LiqRequest({
            txData: LiqRequestTxSata,
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: DepositAmount
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: VaultAmount,
            outputAmount: VaultOutputAmount,
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

        uint256 actual = DepositAmount - 1;
        vm.expectRevert(abi.encodeWithSelector(
            P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount.selector,
            actual,
            DepositAmount
        ));
        factory.deposit{value: actual}(
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

    function testAllowedCalldataChecker__NoAllowedCalldata() public {
        _doDeposit();

        address yieldProtocolAddress = makeAddr("yieldProtocolAddress");
        bytes memory yieldProtocolCalldata = new bytes(42);

        vm.startPrank(clientAddress);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        IP2pSuperformProxy(proxyAddress).callAnyFunction(
            yieldProtocolAddress,
            yieldProtocolCalldata
        );
        vm.stopPrank();
    }

    function testP2pSuperformProxy_GetClientAddress() public {
        _doDeposit();
        
        assertEq(IP2pSuperformProxy(proxyAddress).getClient(), clientAddress);
    }

    function testP2pSuperformProxy_GetP2pTreasuryAddress() public {
        _doDeposit();
        
        assertEq(IP2pSuperformProxy(proxyAddress).getP2pTreasury(), P2pTreasury);
    }

    function testP2pSuperformProxy_GetClientBasisPointsOfDeposit() public {
        _doDeposit();
        
        assertEq(IP2pSuperformProxy(proxyAddress).getClientBasisPointsOfDeposit(), ClientBasisPointsOfDeposit);
    }

    function testP2pSuperformProxy_GetClientBasisPointsOfProfit() public {
        _doDeposit();
        
        assertEq(IP2pSuperformProxy(proxyAddress).getClientBasisPointsOfProfit(), ClientBasisPointsOfProfit);
    }

    function testP2pSuperformProxyFactory_GetP2pOperatorAddress() public view {
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);
    }

    function testP2pSuperformProxyFactory_GetP2pSignerAddress() public view {
        assertEq(factory.getP2pSigner(), p2pSignerAddress);
    }

    function testP2pSuperformProxyFactory_GetClientToProxy() public {
        _doDeposit();
        
        address proxy = factory.predictP2pYieldProxyAddress(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit
        );
        assertEq(proxy, proxyAddress);
    }

    function testAllowedCalldataCheckerUpgrade() public {
        _doDeposit();

        address yieldProtocolAddress = makeAddr("yieldProtocolAddress");
        bytes memory yieldProtocolCalldata = new bytes(42);

        vm.startPrank(clientAddress);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        IP2pSuperformProxy(proxyAddress).callAnyFunction(
            yieldProtocolAddress,
            yieldProtocolCalldata
        );
        vm.stopPrank();

        vm.startPrank(p2pOperatorAddress);
        MockAllowedCalldataChecker newImplementation = new MockAllowedCalldataChecker();
        admin.upgrade(ITransparentUpgradeableProxy(address(tup)), address(newImplementation));
        vm.stopPrank();

        vm.startPrank(clientAddress);
        vm.expectRevert("Address: call to non-contract");
        IP2pSuperformProxy(proxyAddress).callAnyFunction(
            yieldProtocolAddress,
            yieldProtocolCalldata
        );
        vm.stopPrank();
    }

    function testP2pSuperformProxy_CheckClaim_UnauthorizedAccount() public {
        _doDeposit();
        
        address unauthorizedClaimer = makeAddr("unauthorizedClaimer");
        uint256[] memory periodIds = new uint256[](1);
        periodIds[0] = 1;
        
        address[][] memory rewardTokens = new address[][](1);
        rewardTokens[0] = new address[](1);
        rewardTokens[0][0] = makeAddr("rewardToken");
        
        uint256[][] memory amountsClaimed = new uint256[][](1);
        amountsClaimed[0] = new uint256[](1);
        amountsClaimed[0][0] = 100;
        
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(0);
        
        vm.startPrank(unauthorizedClaimer);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, unauthorizedClaimer));
        IP2pSuperformProxy(proxyAddress).batchClaim(
            periodIds,
            rewardTokens,
            amountsClaimed,
            proofs
        );
        vm.stopPrank();
    }

    function testP2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);

        LiqRequest memory liqRequest = LiqRequest({
            txData: LiqRequestTxSata,
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: DepositAmount
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: VaultAmount,
            outputAmount: VaultOutputAmount,
            maxSlippage: 500,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: address(0x123), // Setting to a different address than proxyAddress
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        vm.expectRevert(abi.encodeWithSelector(P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy.selector, address(0x123)));
        factory.deposit{value: DepositAmount}(
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

    function testP2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);

        LiqRequest memory liqRequest = LiqRequest({
            txData: LiqRequestTxSata,
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: DepositAmount
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: VaultAmount,
            outputAmount: VaultOutputAmount,
            maxSlippage: 500,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: proxyAddress,
            receiverAddressSP: address(0x123), // Setting to a different address than proxyAddress
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        vm.expectRevert(abi.encodeWithSelector(P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy.selector, address(0x123)));
        factory.deposit{value: DepositAmount}(
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

    function testP2pSuperformProxy__ShouldNotRetain4626() public {
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);

        LiqRequest memory liqRequest = LiqRequest({
            txData: LiqRequestTxSata,
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: DepositAmount
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: VaultAmount,
            outputAmount: VaultOutputAmount,
            maxSlippage: 500,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: true, // Setting retain4626 to true
            receiverAddress: proxyAddress,
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({
            superformData: superformData
        });

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        vm.expectRevert(P2pSuperformProxy__ShouldNotRetain4626.selector);
        factory.deposit{value: DepositAmount}(
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

    function _getVaultAddress() private pure returns(address) {
        return address(uint160(SuperformId));
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
        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy;
        bytes memory permit2SignatureForP2pYieldProxy;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        vm.startPrank(clientAddress);

        LiqRequest memory liqRequest = LiqRequest({
            txData: LiqRequestTxSata,
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: DepositAmount
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: VaultAmount,
            outputAmount: VaultOutputAmount,
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

        factory.deposit{value: DepositAmount * 113 / 100}(
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
            txData: hex'4630a0d8043bf297c37e0f5ca30079351a85da894514103f8da67224f7bb0b337a1ff61300000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000fd35454f266dc9f672985260029f1686c6b6036c000000000000000000000000000000000000000000000000000227962180fd4f0000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a3078303030303030303030303030303030303030303030303030303030303030303030303030303030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000060e8c01e8e39b10202e39e62001f08092cc03ca000000000000000000000000060e8c01e8e39b10202e39e62001f08092cc03ca0000000000000000000000001f32b1c2345538c0c6f582fcb022739c4a194ebb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000039843d934a78a00000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001642646478b0000000000000000000000001f32b1c2345538c0c6f582fcb022739c4a194ebb00000000000000000000000000000000000000000000000000039843d934a78a000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000227962180fd4f0000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae00000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000070021f32b1c2345538c0c6f582fcb022739c4a194ebb01ffff01bf30ff33cf9c6b0c48702ff17891293b002dfea401060e8c01e8e39b10202e39e62001f08092cc03ca01420000000000000000000000000000000000000601ffff02001231deb6f5749ef6ce6943a275a1d3e7486f4eae0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
            token: NATIVE,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 10,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: 1011008197038423,
            outputAmount: 1011842104469386,
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