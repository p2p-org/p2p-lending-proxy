// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/adapters/morpho/MorphoRewardsAllowedCalldataChecker.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/mocks/@murky/Merkle.sol";
import "../../src/mocks/IUniversalRewardsDistributor.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetProtocolEvents is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant VAULT_USDC = 0x8eB67A509616cd6A7c1B3c8C21D48FF57df3d458;
    address constant DISTRIBUTOR = 0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb;
    address constant MORPHO_TOKEN = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address constant MORPHO_OWNER = 0xcBa28b38103307Ec8dA98377ffF9816C164f9AFa;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant SIG_DEADLINE = 1_734_464_723;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000;
    bytes32 private constant ERC4626_DEPOSIT_EVENT = keccak256("Deposit(address,address,uint256,uint256)");
    bytes32 private constant ERC4626_WITHDRAW_EVENT = keccak256("Withdraw(address,address,address,uint256,uint256)");
    bytes32 private constant ERC20_TRANSFER_EVENT = keccak256("Transfer(address,address,uint256)");

    P2pYieldProxyFactory private factory;
    address private client;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;
    Merkle private merkle;

    ProxyAdmin private opCheckerAdmin;
    TransparentUpgradeableProxy private opCheckerProxy;

    function setUp() public {
        vm.createSelectFork("mainnet", 21_308_893);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");
        merkle = new Merkle();

        vm.startPrank(p2pOperator);

        AllowedCalldataChecker denyAll = new AllowedCalldataChecker();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        opCheckerAdmin = new ProxyAdmin();
        opCheckerProxy = new TransparentUpgradeableProxy(address(denyAll), address(opCheckerAdmin), initData);

        ProxyAdmin c2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy c2pCheckerProxy =
            new TransparentUpgradeableProxy(address(denyAll), address(c2pAdmin), initData);

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

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    function test_morpho_mainnet_deposit_withdraw_and_claim_emit_protocol_events() external {
        deal(USDC, client, 100e6);

        vm.recordLogs();
        _doDeposit();
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, VAULT_USDC, ERC4626_DEPOSIT_EVENT);

        uint256 shares = IERC20(VAULT_USDC).balanceOf(proxyAddress);
        assertGt(shares, 0);

        vm.recordLogs();
        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).withdraw(VAULT_USDC, shares / 2);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertEventSeen(withdrawLogs, VAULT_USDC, ERC4626_WITHDRAW_EVENT);

        // URD claim via claimAdditionalRewardTokens
        _upgradeOpChecker();

        uint256 claimable = 1 ether;
        bytes32[] memory tree = _setupRewards(claimable);
        bytes32[] memory proof = merkle.getProof(tree, 0);

        bytes memory claimCalldata = abi.encodeCall(
            IUniversalRewardsDistributorBase.claim,
            (proxyAddress, MORPHO_TOKEN, claimable, proof)
        );
        address[] memory tokens = new address[](1);
        tokens[0] = MORPHO_TOKEN;

        vm.recordLogs();
        vm.prank(client);
        P2pErc4626Proxy(proxyAddress).claimAdditionalRewardTokens(DISTRIBUTOR, claimCalldata, tokens);
        Vm.Log[] memory claimLogs = vm.getRecordedLogs();
        _assertEventSeen(claimLogs, MORPHO_TOKEN, ERC20_TRANSFER_EVENT);
    }

    function _doDeposit() private {
        bytes memory signerSignature = _getP2pSignerSignature();

        vm.startPrank(client);
        IERC20(USDC).safeApprove(proxyAddress, 0);
        IERC20(USDC).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, VAULT_USDC, DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signerSignature);
        vm.stopPrank();
    }

    function _setupRewards(uint256 _claimable) private returns (bytes32[] memory tree) {
        tree = new bytes32[](2);
        tree[0] = keccak256(bytes.concat(keccak256(abi.encode(proxyAddress, MORPHO_TOKEN, _claimable))));
        tree[1] = keccak256(bytes.concat(keccak256(abi.encode(address(0xdead), MORPHO_TOKEN, _claimable))));
        bytes32 root = merkle.getRoot(tree);

        vm.prank(MORPHO_OWNER);
        IUniversalRewardsDistributor(DISTRIBUTOR).setRoot(root, bytes32(0));
    }

    function _getP2pSignerSignature() private view returns (bytes memory) {
        bytes32 hashForSigner = factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, SIG_DEADLINE);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _assertEventSeen(Vm.Log[] memory _logs, address _emitter, bytes32 _topic0) private pure {
        uint256 logsLength = _logs.length;
        for (uint256 i; i < logsLength; ++i) {
            Vm.Log memory log = _logs[i];
            if (log.emitter == _emitter && log.topics.length > 0 && log.topics[0] == _topic0) {
                return;
            }
        }
        revert("EVENT_NOT_FOUND");
    }

    function _upgradeOpChecker() private {
        MorphoRewardsAllowedCalldataChecker impl = new MorphoRewardsAllowedCalldataChecker();
        vm.prank(p2pOperator);
        opCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(opCheckerProxy)), address(impl));
    }
}
