// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../lib/forge-std/src/Vm.sol";
import "../src/adapters/superform/p2pSuperformProxyFactory/P2pSuperformProxyFactory.sol";
import {Script} from "forge-std/Script.sol";
import {PermitHash} from "../src/@permit2/libraries/PermitHash.sol";

contract RunTestDepositBase is Script {
    using SafeERC20 for IERC20;

    address constant SuperformRouter = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address constant SuperPositions = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address constant P2pTreasury = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;

    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 constant SigDeadline = 1743997707;
    uint48 constant ClientBasisPointsOfProfit = 8700; // 13% fee
    uint48 constant ClientBasisPointsOfDeposit = 10000; // 0% fee
    uint256 constant DepositAmount = 123400;
    uint256 constant SharesAmount = 1222092;
    uint256 constant SuperformId = 53060340969225753329461353767745054384708953976330005872281754;

    P2pSuperformProxyFactory factory;
    address proxyAddress;

    function run()
    external
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerKey);

        factory = P2pSuperformProxyFactory(0x27aC94F64Fa26d8E26e3833c6E0ce7e24227656D);
        proxyAddress = factory.predictP2pYieldProxyAddress(
            wallet.addr,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit
        );

        IAllowanceTransfer.PermitSingle memory permitSingleForP2pYieldProxy = _getPermitSingleForP2pYieldProxy();
        bytes memory permit2SignatureForP2pYieldProxy = _getPermit2SignatureForP2pYieldProxy(permitSingleForP2pYieldProxy);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            wallet.addr,
            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline
        );

        LiqRequest memory liqRequest = LiqRequest({
            txData: "",
            token: USDC,
            interimToken: address(0),
            bridgeId: 1,
            liqDstChainId: 0,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: DepositAmount,
            outputAmount: SharesAmount,
            maxSlippage: 50,
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

        bytes memory superformCalldata = hex'b19dcc3300000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000210500000001668bcc80d9b85de4e683a5e1d64946e175a3a748000000000000000000000000000000000000000000000000000000000001e208000000000000000000000000000000000000000000000000000000000001dcb600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000024000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e1158d9158d41186994b400ab833b85284f2e06c000000000000000000000000e1158d9158d41186994b400ab833b85284f2e06c000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'; //abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        vm.startBroadcast(deployerKey);
        if (IERC20(USDC).allowance(wallet.addr, address(Permit2Lib.PERMIT2)) == 0) {
            IERC20(USDC).safeApprove(address(Permit2Lib.PERMIT2), type(uint256).max);
        }
        factory.deposit(
            permitSingleForP2pYieldProxy,
            permit2SignatureForP2pYieldProxy,

            superformCalldata,

            ClientBasisPointsOfDeposit,
            ClientBasisPointsOfProfit,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopBroadcast();
    }

    function _getPermitSingleForP2pYieldProxy() private returns(IAllowanceTransfer.PermitSingle memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerKey);
        (, , uint48 nonce) = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3).allowance(wallet.addr, USDC, proxyAddress);

        IAllowanceTransfer.PermitDetails memory permitDetails = IAllowanceTransfer.PermitDetails({
            token: USDC,
            amount: uint160(DepositAmount),
            expiration: uint48(SigDeadline),
            nonce: nonce
        });

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
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(vm.envUint("PRIVATE_KEY"), permitSingleForP2pYieldProxyHash);
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
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(vm.envUint("PRIVATE_KEY"), ethSignedMessageHashForP2pSigner);
        bytes memory p2pSignerSignature = abi.encodePacked(r2, s2, v2);
        return p2pSignerSignature;
    }
}

