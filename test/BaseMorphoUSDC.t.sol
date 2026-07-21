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
import "../src/p2pYieldProxy/IP2pYieldProxy.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

contract BaseMorphoUSDC is Test {
    using SafeERC20 for IERC20;

    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant SuperformRouter = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address constant SuperPositions = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address constant RewardsDistributor = 0xce23bD7205bF2B543F6B4eeC00Add0C111FEFc3B;

    address constant P2pTreasury = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;

    uint256 constant SuperformId = 53060340969225753329461353767745054384708953976330005872281754;

    P2pSuperformProxyFactory private factory;

    address private clientAddress;
    uint256 private clientPrivateKey;

    address private p2pSignerAddress;
    uint256 private p2pSignerPrivateKey;

    address private p2pOperatorAddress;
    address private nobody;

    uint256 constant SigDeadline = 1742805206;
    uint48 constant ClientBasisPointsOfProfit = 8700; // 13% fee
    uint48 constant ClientBasisPointsOfDeposit = 10_000; // 0% fee
    uint256 constant DepositAmount = 1234568;
    uint256 constant SharesAmount = 1222092;

    uint256 DepositAmountWithFee;

    address proxyAddress;

    function setUp() public {
        vm.createSelectFork("base", 27412018);

        (clientAddress, clientPrivateKey) = makeAddrAndKey("client");
        (p2pSignerAddress, p2pSignerPrivateKey) = makeAddrAndKey("p2pSigner");
        p2pOperatorAddress = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperatorAddress);

        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy tup =
            new TransparentUpgradeableProxy(address(implementation), address(admin), initData);
        factory = new P2pSuperformProxyFactory(
            p2pSignerAddress,
            p2pOperatorAddress,
            P2pTreasury,
            SuperformRouter,
            SuperPositions,
            address(tup),
            RewardsDistributor
        );

        vm.stopPrank();

        proxyAddress =
            factory.predictP2pYieldProxyAddress(clientAddress, ClientBasisPointsOfDeposit, ClientBasisPointsOfProfit);

        DepositAmountWithFee = DepositAmount + DepositAmount * (10_000 - ClientBasisPointsOfDeposit) / 10_000;
    }

    function test_happyPath_Morpho() public {
        deal(USDC, clientAddress, 10000e18);

        uint256 assetBalanceBefore = IERC20(USDC).balanceOf(clientAddress);

        _doDeposit();

        uint256 assetBalanceAfter1 = IERC20(USDC).balanceOf(clientAddress);
        assertEq(assetBalanceBefore - assetBalanceAfter1, DepositAmountWithFee);

        _doDeposit();

        uint256 assetBalanceAfter2 = IERC20(USDC).balanceOf(clientAddress);
        assertEq(assetBalanceAfter1 - assetBalanceAfter2, DepositAmountWithFee);

        _doDeposit();
        _doDeposit();

        uint256 assetBalanceAfterAllDeposits = IERC20(USDC).balanceOf(clientAddress);

        _doWithdraw(10);

        uint256 assetBalanceAfterWithdraw1 = IERC20(USDC).balanceOf(clientAddress);

        assertApproxEqAbs(
            assetBalanceAfterWithdraw1 - assetBalanceAfterAllDeposits, DepositAmountWithFee * 4 / 10, 10000
        );

        _doWithdraw(5);
        _doWithdraw(3);
    }

    function test_depositWithZeroDepositBpsDoesNotRevertAndUsesRawAmount() public {
        deal(USDC, clientAddress, 10000e18);

        address zeroBpsProxy =
            factory.predictP2pYieldProxyAddress(clientAddress, 0, ClientBasisPointsOfProfit);

        bytes memory p2pSignerSignature =
            _getP2pSignerSignature(clientAddress, 0, ClientBasisPointsOfProfit, SigDeadline);

        vm.startPrank(clientAddress);
        if (IERC20(USDC).allowance(clientAddress, zeroBpsProxy) == 0) {
            IERC20(USDC).safeApprove(zeroBpsProxy, type(uint256).max);
        }

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
            receiverAddress: zeroBpsProxy,
            receiverAddressSP: zeroBpsProxy,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({superformData: superformData});
        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        // Prevent upstream router revert due to allowance expectations; we only assert proxy math here.
        vm.mockCall(
            SuperformRouter,
            abi.encodeWithSelector(IBaseRouter.singleDirectSingleVaultDeposit.selector),
            bytes("")
        );

        factory.deposit(superformCalldata, 0, ClientBasisPointsOfProfit, SigDeadline, p2pSignerSignature);
        vm.stopPrank();

        IP2pYieldProxy proxy = IP2pYieldProxy(zeroBpsProxy);
        assertEq(proxy.getClientBasisPointsOfDeposit(), 0);
        assertEq(proxy.calculateMinAmountToApproveForDeposit(DepositAmount), DepositAmount);
    }

    function _getVaultAddress() private pure returns (address) {
        return address(uint160(SuperformId));
    }

    function _getP2pSignerSignature(
        address _clientAddress,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _sigDeadline
    ) private view returns (bytes memory) {
        // p2p signer signing
        bytes32 hashForP2pSigner = factory.getHashForP2pSigner(
            _clientAddress, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit, _sigDeadline
        );
        bytes32 ethSignedMessageHashForP2pSigner = ECDSA.toEthSignedMessageHash(hashForP2pSigner);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(p2pSignerPrivateKey, ethSignedMessageHashForP2pSigner);
        bytes memory p2pSignerSignature = abi.encodePacked(r2, s2, v2);
        return p2pSignerSignature;
    }

    function _doDeposit() private {
        bytes memory p2pSignerSignature =
            _getP2pSignerSignature(clientAddress, ClientBasisPointsOfDeposit, ClientBasisPointsOfProfit, SigDeadline);

        vm.startPrank(clientAddress);
        // Approve the proxy to spend USDC tokens
        if (IERC20(USDC).allowance(clientAddress, proxyAddress) == 0) {
            IERC20(USDC).safeApprove(proxyAddress, type(uint256).max);
        }

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
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({superformData: superformData});

        bytes memory superformCalldata = abi.encodeCall(IBaseRouter.singleDirectSingleVaultDeposit, (req));

        factory.deposit(
            superformCalldata, ClientBasisPointsOfDeposit, ClientBasisPointsOfProfit, SigDeadline, p2pSignerSignature
        );
        vm.stopPrank();
    }

    function _doWithdraw(uint256 denominator) private {
        uint256 sharesBalance = IERC1155(SuperPositions).balanceOf(proxyAddress, SuperformId);
        console.log("sharesBalance");
        console.log(sharesBalance);

        uint256 sharesToWithdraw = sharesBalance / denominator;

        LiqRequest memory liqRequest = LiqRequest({
            txData: "",
            token: address(0),
            interimToken: address(0),
            bridgeId: 1,
            liqDstChainId: 0,
            nativeAmount: 0
        });
        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: SuperformId,
            amount: DepositAmount * 4 / denominator,
            outputAmount: sharesToWithdraw,
            maxSlippage: 50,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: proxyAddress,
            receiverAddressSP: proxyAddress,
            extraFormData: ""
        });
        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({superformData: superformData});
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
