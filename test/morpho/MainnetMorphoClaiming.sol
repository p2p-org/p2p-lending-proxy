// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/adapters/morpho/MorphoRewardsAllowedCalldataChecker.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/mocks/@murky/Merkle.sol";
import "../../src/mocks/IUniversalRewardsDistributor.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetMorphoClaiming is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant VAULT_USDC = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant VAULT_USDT = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;

    address constant DISTRIBUTOR = 0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb;
    address constant MORPHO_TOKEN = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address constant MORPHO_OWNER = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;

    uint256 constant SIG_DEADLINE = 1734464723;
    uint96 constant CLIENT_BASIS_POINTS = 8700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000;

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private clientKey;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private referenceProxy;

    address private proxyAddress;
    Merkle internal merkle;

    // Checker proxies + admins for upgrades
    ProxyAdmin private opCheckerAdmin;
    TransparentUpgradeableProxy private opCheckerProxy;
    ProxyAdmin private c2pCheckerAdmin;
    TransparentUpgradeableProxy private c2pCheckerProxy;

    address asset;
    address vault;

    function setUp() public {
        vm.createSelectFork("mainnet", 21308893);

        (client, clientKey) = makeAddrAndKey("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker denyAll = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        opCheckerAdmin = new ProxyAdmin();
        opCheckerProxy = new TransparentUpgradeableProxy(address(denyAll), address(opCheckerAdmin), initData);

        c2pCheckerAdmin = new ProxyAdmin();
        c2pCheckerProxy = new TransparentUpgradeableProxy(address(denyAll), address(c2pCheckerAdmin), initData);

        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pErc4626Proxy(
                address(factory),
                P2P_TREASURY,
                address(opCheckerProxy),
                address(c2pCheckerProxy)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BASIS_POINTS);
        merkle = new Merkle();
        asset = USDC;
        vault = VAULT_USDC;
    }

    function test_morpho_MorphoClaimingByClient() external {
        uint256 claimable = 10 ether;

        deal(asset, client, 100e6);
        _doDeposit();

        // Upgrade operator's checker so client can call claimAdditionalRewardTokens
        _upgradeOpChecker();

        bytes32[] memory tree = _setupRewards(claimable);
        bytes32[] memory proof = merkle.getProof(tree, 0);

        uint256 clientBalanceBefore = IERC20(MORPHO_TOKEN).balanceOf(client);
        uint256 treasuryBalanceBefore = IERC20(MORPHO_TOKEN).balanceOf(P2P_TREASURY);

        // Build URD claim calldata
        bytes memory claimCalldata = abi.encodeCall(
            IUniversalRewardsDistributorBase.claim,
            (proxyAddress, MORPHO_TOKEN, claimable, proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = MORPHO_TOKEN;

        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(DISTRIBUTOR, claimCalldata, tokens);

        uint256 clientBalanceAfter = IERC20(MORPHO_TOKEN).balanceOf(client);
        uint256 treasuryBalanceAfter = IERC20(MORPHO_TOKEN).balanceOf(P2P_TREASURY);

        assertEq(clientBalanceAfter - clientBalanceBefore, claimable * CLIENT_BASIS_POINTS / 10_000);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, claimable * (10_000 - CLIENT_BASIS_POINTS) / 10_000);
    }

    function test_morpho_MorphoClaimingByOperator() external {
        uint256 claimable = 5 ether;

        deal(asset, client, 50e6);
        _doDeposit();

        // Upgrade client's checker so operator can call claimAdditionalRewardTokens
        _upgradeC2pChecker();

        bytes32[] memory tree = _setupRewards(claimable);
        bytes32[] memory proof = merkle.getProof(tree, 0);

        uint256 clientBalanceBefore = IERC20(MORPHO_TOKEN).balanceOf(client);
        uint256 treasuryBalanceBefore = IERC20(MORPHO_TOKEN).balanceOf(P2P_TREASURY);

        bytes memory claimCalldata = abi.encodeCall(
            IUniversalRewardsDistributorBase.claim,
            (proxyAddress, MORPHO_TOKEN, claimable, proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = MORPHO_TOKEN;

        vm.startPrank(p2pOperator);
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(DISTRIBUTOR, claimCalldata, tokens);
        vm.stopPrank();

        uint256 clientBalanceAfter = IERC20(MORPHO_TOKEN).balanceOf(client);
        uint256 treasuryBalanceAfter = IERC20(MORPHO_TOKEN).balanceOf(P2P_TREASURY);

        assertEq(clientBalanceAfter - clientBalanceBefore, claimable * CLIENT_BASIS_POINTS / 10_000);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, claimable * (10_000 - CLIENT_BASIS_POINTS) / 10_000);
    }

    function _setupRewards(uint256 claimable) internal returns (bytes32[] memory tree) {
        tree = new bytes32[](2);
        tree[0] = keccak256(bytes.concat(keccak256(abi.encode(proxyAddress, MORPHO_TOKEN, claimable))));
        tree[1] = keccak256(bytes.concat(keccak256(abi.encode(address(0xdead), MORPHO_TOKEN, claimable))));
        bytes32 root = merkle.getRoot(tree);

        vm.prank(MORPHO_OWNER);
        IUniversalRewardsDistributor(DISTRIBUTOR).setRoot(root, bytes32(0));
    }

    function _doDeposit() private {
        bytes memory signerSignature = _getP2pSignerSignature(client, CLIENT_BASIS_POINTS, SIG_DEADLINE);

        vm.startPrank(client);
        IERC20(asset).safeApprove(proxyAddress, 0);
        IERC20(asset).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, vault, DEPOSIT_AMOUNT, CLIENT_BASIS_POINTS, SIG_DEADLINE, signerSignature);
        vm.stopPrank();
    }

    function _getP2pSignerSignature(address _client, uint96 _clientBasisPoints, uint256 _sigDeadline)
        private
        view
        returns (bytes memory)
    {
        bytes32 hashForSigner = factory.getHashForP2pSigner(
            referenceProxy,
            _client,
            _clientBasisPoints,
            _sigDeadline
        );
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _upgradeOpChecker() private {
        MorphoRewardsAllowedCalldataChecker impl = new MorphoRewardsAllowedCalldataChecker();
        vm.prank(p2pOperator);
        opCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(opCheckerProxy)), address(impl));
    }

    function _upgradeC2pChecker() private {
        MorphoRewardsAllowedCalldataChecker impl = new MorphoRewardsAllowedCalldataChecker();
        vm.prank(p2pOperator);
        c2pCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(c2pCheckerProxy)), address(impl));
    }
}
