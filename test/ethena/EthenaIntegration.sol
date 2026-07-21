// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/access/P2pOperator.sol";
import "../../src/adapters/ethena/@ethena/IStakedUSDe.sol";
import "../../src/adapters/ethena/p2pEthenaProxy/P2pEthenaProxy.sol";
import "../../src/adapters/ethena/p2pEthenaProxy/IP2pEthenaProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxy/IP2pYieldProxy.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "../../src/p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

contract EthenaIntegration is Test {
    using SafeERC20 for IERC20;

    address constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant P2pTreasury = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;

    P2pYieldProxyFactory private factory;
    address private referenceProxy;

    address private clientAddress;
    uint256 private clientPrivateKey;

    address private p2pSignerAddress;
    uint256 private p2pSignerPrivateKey;

    address private p2pOperatorAddress;
    address private nobody;

    uint256 constant SigDeadline = 1734464723;
    uint96 constant ClientBasisPoints = 8700; // 13% fee
    uint256 constant DepositAmount = 10 ether;

    address proxyAddress;

    function setUp() public {
        vm.createSelectFork("mainnet", 21308893);

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
        referenceProxy = address(new P2pEthenaProxy(address(factory), P2pTreasury, address(tup), address(clientToP2pTup), sUSDe, USDe));
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints);
    }

    function test_ethena_happyPath_Mainnet() public {
        deal(USDe, clientAddress, 10_000e18);

        uint256 assetBalanceBefore = IERC20(USDe).balanceOf(clientAddress);

        _doDeposit();

        uint256 assetBalanceAfter1 = IERC20(USDe).balanceOf(clientAddress);
        assertEq(assetBalanceBefore - assetBalanceAfter1, DepositAmount);

        _doDeposit();

        uint256 assetBalanceAfter2 = IERC20(USDe).balanceOf(clientAddress);
        assertEq(assetBalanceAfter1 - assetBalanceAfter2, DepositAmount);

        _doDeposit();
        _doDeposit();

        uint256 assetBalanceAfterAllDeposits = IERC20(USDe).balanceOf(clientAddress);

        _doWithdraw(10);

        uint256 assetBalanceAfterWithdraw1 = IERC20(USDe).balanceOf(clientAddress);

        uint256 withdrawnPortion = assetBalanceAfterWithdraw1 - assetBalanceAfterAllDeposits;
        assertGt(withdrawnPortion, 0, "Expected partial withdrawal to return funds");

        _doWithdraw(5);
        _doWithdraw(3);
        _doWithdraw(2);
        _doWithdraw(1);

        uint256 assetBalanceAfterAllWithdrawals = IERC20(USDe).balanceOf(clientAddress);
        assertGt(assetBalanceAfterAllWithdrawals, assetBalanceBefore, "Expected non-zero profit");
    }

    function test_ethena_profitSplit_Mainnet() public {
        deal(USDe, clientAddress, 100e18);

        uint256 clientAssetBalanceBefore = IERC20(USDe).balanceOf(clientAddress);
        uint256 p2pAssetBalanceBefore = IERC20(USDe).balanceOf(P2pTreasury);

        _doDeposit();

        _forward(10_000); // simulate time to accrue yield

        _doWithdraw(1);

        uint256 clientAssetBalanceAfter = IERC20(USDe).balanceOf(clientAddress);
        uint256 p2pAssetBalanceAfter = IERC20(USDe).balanceOf(P2pTreasury);
        uint256 clientBalanceChange = clientAssetBalanceAfter - clientAssetBalanceBefore;
        uint256 p2pBalanceChange = p2pAssetBalanceAfter - p2pAssetBalanceBefore;

        assertGt(clientBalanceChange, 0, "Client expected to receive profit");
        assertGt(p2pBalanceChange, 0, "P2P treasury expected to receive profit share");
        assertGt(clientBalanceChange, p2pBalanceChange, "Client share should be greater than treasury share");
    }

    function test_ethena_transferP2pSigner_Mainnet() public {
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pSigner(nobody);
        vm.stopPrank();

        assertEq(factory.getP2pSigner(), nobody);
    }

    function test_ethena_getHashForP2pSigner_Mainnet() public view {
                bytes32 expected = keccak256(
            abi.encode(
                referenceProxy,
                clientAddress,
                ClientBasisPoints,
                SigDeadline,
                address(factory),
                block.chainid
            )
        );
        bytes32 actual = factory.getHashForP2pSigner(referenceProxy, clientAddress, ClientBasisPoints, SigDeadline);
        assertEq(actual, expected);
    }

    function test_ethena_predictP2pYieldProxyAddress_Mainnet() public view {
        address predicted = factory.predictP2pYieldProxyAddress(referenceProxy, clientAddress, ClientBasisPoints);
        assertEq(predicted, proxyAddress);
    }

    function test_ethena_getReferenceP2pYieldProxy_Mainnet() public view {
                assertTrue(referenceProxy != address(0), "reference should be deployed");
    }

    function test_ethena_getAllProxies_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();
        address[] memory proxies = factory.getAllProxies();
        assertEq(proxies.length, 1);
        assertEq(proxies[0], proxyAddress);
    }

    function test_ethena_getAllProxiesAfterSecondDeposit_Mainnet() public {
        deal(USDe, clientAddress, 2 * DepositAmount);
        _doDeposit();
        _doDeposit();
        address[] memory proxies = factory.getAllProxies();
        assertEq(proxies.length, 1);
        assertEq(proxies[0], proxyAddress);
    }

    function test_ethena_getP2pSignerAddress_Mainnet() public view {
        assertEq(factory.getP2pSigner(), p2pSignerAddress);
    }

    function test_ethena_invalidP2pSignerSignature_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        (address rogueSigner, uint256 roguePrivateKey) = makeAddrAndKey("rogueSigner");
        vm.label(rogueSigner, "rogueSigner");

        bytes memory invalidSignature = _getP2pSignerSignatureWithKey(
            clientAddress,
            ClientBasisPoints,
            SigDeadline,
            roguePrivateKey
        );

        vm.startPrank(clientAddress);
        _ensureProxyAllowance(DepositAmount);
        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);
        factory.deposit(
            referenceProxy,
            USDe,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            invalidSignature
        );
        vm.stopPrank();
    }

    function test_ethena_p2pSignerSignatureExpired_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory signature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            expiredDeadline
        );

        vm.startPrank(clientAddress);
        _ensureProxyAllowance(DepositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxyFactory__P2pSignerSignatureExpired.selector,
                expiredDeadline
            )
        );
        factory.deposit(
            referenceProxy,
            USDe,
            DepositAmount,
            ClientBasisPoints,
            expiredDeadline,
            signature
        );
        vm.stopPrank();
    }

    function test_ethena_depositRequiresAllowance_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);

        bytes memory signature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        factory.deposit(
            referenceProxy,
            USDe,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            signature
        );
        vm.stopPrank();
    }

    function test_ethena_viewFunctions_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        assertEq(factory.getP2pOperator(), p2pOperatorAddress);
        assertEq(factory.getP2pSigner(), p2pSignerAddress);

        P2pEthenaProxy proxy = P2pEthenaProxy(proxyAddress);
        assertEq(proxy.getFactory(), address(factory));
        assertEq(proxy.getP2pTreasury(), P2pTreasury);
        assertEq(proxy.getClient(), clientAddress);
        assertEq(proxy.getClientBasisPoints(), ClientBasisPoints);
        assertEq(proxy.getTotalDeposited(USDe), DepositAmount);
        assertEq(proxy.getTotalWithdrawn(USDe), 0);
    }

    function test_ethena_supportsInterface_Mainnet() public {
        bool factorySupports = factory.supportsInterface(type(IP2pYieldProxyFactory).interfaceId);
        assertTrue(factorySupports, "factory should expose interface id");

        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();
        bool proxySupportsEthena = P2pEthenaProxy(proxyAddress).supportsInterface(type(IP2pEthenaProxy).interfaceId);
        bool proxySupportsYield = P2pEthenaProxy(proxyAddress).supportsInterface(type(IP2pYieldProxy).interfaceId);
        assertTrue(proxySupportsEthena, "proxy should expose Ethena interface");
        assertTrue(proxySupportsYield, "proxy should expose base yield interface");
    }

    function test_ethena_operatorCooldownAssets_RevertsWithoutAccruedRewards_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(P2pEthenaProxy__ZeroAccruedRewards.selector);
        P2pEthenaProxy(proxyAddress).cooldownAssetsAccruedRewards();
        vm.stopPrank();
    }

    function test_ethena_getHashForP2pSignerMatchesSignature_Mainnet() public view {
        bytes32 hash = factory.getHashForP2pSigner(referenceProxy, clientAddress, ClientBasisPoints, SigDeadline);
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerPrivateKey, signedHash);
        address recovered = ECDSA.recover(signedHash, v, r, s);
        assertEq(recovered, p2pSignerAddress);
    }

    function test_ethena_withdrawViaCallAnyFunction_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        bytes memory withdrawalCallData = abi.encodeCall(
            IStakedUSDe.unstake,
            clientAddress
        );

        vm.startPrank(clientAddress);
        vm.expectRevert(
            abi.encodeWithSelector(AllowedCalldataChecker__NoAllowedCalldata.selector)
        );
        P2pEthenaProxy(proxyAddress).callAnyFunction(USDe, withdrawalCallData);
        vm.stopPrank();
    }


    function test_ethena_transferP2pOperator_Mainnet() public {
        address newOperator = makeAddr("newOperator");

        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pOperator(newOperator);
        vm.stopPrank();

        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.acceptP2pOperator();
        vm.stopPrank();

        vm.startPrank(newOperator);
        factory.acceptP2pOperator();
        vm.stopPrank();

        assertEq(factory.getP2pOperator(), newOperator);
        assertEq(factory.getPendingP2pOperator(), address(0));
    }

    function test_ethena_clientBasisPointsGreaterThan10000_Mainnet() public {
        uint96 invalidBasisPoints = 10_001;

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            invalidBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        _ensureProxyAllowance(DepositAmount);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__InvalidClientBasisPoints.selector, invalidBasisPoints));
        factory.deposit(
            referenceProxy,
            USDe,
            DepositAmount,
            invalidBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_ethena_zeroAddressAsset_Mainnet() public {
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        vm.expectRevert(abi.encodeWithSelector(P2pEthenaProxy__InvalidDepositAsset.selector, address(0)));
        factory.deposit(
            referenceProxy,
            address(0),
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_ethena_zeroAssetAmount_Mainnet() public {
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        vm.expectRevert(P2pYieldProxy__ZeroAssetAmount.selector);
        factory.deposit(
            referenceProxy,
            USDe,
            0,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_ethena_depositDirectlyOnProxy_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        vm.startPrank(clientAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotFactoryCalled.selector,
                clientAddress,
                address(factory)
            )
        );
        P2pEthenaProxy(proxyAddress).deposit(USDe, DepositAmount);
        vm.stopPrank();
    }

    function test_ethena_initializeDirectlyOnProxy_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        vm.startPrank(clientAddress);
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        P2pEthenaProxy(proxyAddress).initialize(clientAddress, ClientBasisPoints);
        vm.stopPrank();
    }

    function test_ethena_withdrawOnProxyOnlyCallableByClient_Mainnet() public {
        deal(USDe, clientAddress, DepositAmount);
        _doDeposit();

        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotClientCalled.selector,
                nobody,
                clientAddress
            )
        );
        P2pEthenaProxy(proxyAddress).withdrawAfterCooldown();
        vm.stopPrank();
    }

    function _doDeposit() private {
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        _ensureProxyAllowance(DepositAmount);
        factory.deposit(
            referenceProxy,
            USDe,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function _ensureProxyAllowance(uint256 _requiredAmount) private {
        uint256 currentAllowance = IERC20(USDe).allowance(clientAddress, proxyAddress);
        if (currentAllowance < _requiredAmount) {
            if (currentAllowance != 0) {
                IERC20(USDe).safeApprove(proxyAddress, 0);
            }
            IERC20(USDe).safeApprove(proxyAddress, type(uint256).max);
        }
    }

    function _doWithdraw(uint256 denominator) private {
        uint256 sharesBalance = IERC20(sUSDe).balanceOf(proxyAddress);
        uint256 sharesToWithdraw = sharesBalance / denominator;

        vm.startPrank(clientAddress);
        P2pEthenaProxy(proxyAddress).cooldownShares(sharesToWithdraw);

        _forward(10_000 * 7);

        P2pEthenaProxy(proxyAddress).withdrawAfterCooldown();
        vm.stopPrank();
    }

    function _getP2pSignerSignature(
        address _clientAddress,
        uint96 _clientBasisPoints,
        uint256 _sigDeadline
    ) private view returns (bytes memory) {
        return _getP2pSignerSignatureWithKey(
            _clientAddress,
            _clientBasisPoints,
            _sigDeadline,
            p2pSignerPrivateKey
        );
    }

    function _getP2pSignerSignatureWithKey(
        address _clientAddress,
        uint96 _clientBasisPoints,
        uint256 _sigDeadline,
        uint256 _signerPrivateKey
    ) private view returns (bytes memory) {
        bytes32 hashForP2pSigner = factory.getHashForP2pSigner(referenceProxy, 
            _clientAddress,
            _clientBasisPoints,
            _sigDeadline
        );
        bytes32 ethSignedMessageHashForP2pSigner = ECDSA.toEthSignedMessageHash(hashForP2pSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, ethSignedMessageHashForP2pSigner);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 13);
    }
}
