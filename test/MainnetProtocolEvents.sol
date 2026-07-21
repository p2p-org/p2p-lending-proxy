// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/adapters/resolv/@resolv/IResolvStaking.sol";
import "../src/adapters/resolv/p2pResolvProxy/P2pResolvProxy.sol";
import "../src/common/AllowedCalldataChecker.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetProtocolEvents is Test {
    using SafeERC20 for IERC20;

    address constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address constant stUSR = 0x6c8984bc7DBBeDAf4F6b2FD766f16eBB7d10AAb4;
    address constant RESOLV = 0x259338656198eC7A76c729514D3CB45Dfbf768A1;
    address constant stRESOLV = 0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23;
    address constant P2P_TREASURY = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;
    address constant KNOWN_PROXY = 0x3F888f4E16a08C6B3745dDbaDe98e24569852FA4;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant SIG_DEADLINE = 1_752_690_907;
    uint256 constant DEPOSIT_AMOUNT = 10 ether;
    bytes32 private constant ERC20_TRANSFER_EVENT = keccak256("Transfer(address,address,uint256)");

    P2pYieldProxyFactory private factory;
    address private client;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    function setUp() public {
        vm.createSelectFork("mainnet", 22_730_789);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        vm.startPrank(p2pOperator);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy checkerProxy =
            new TransparentUpgradeableProxy(address(implementation), address(admin), initData);
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pCheckerProxy =
            new TransparentUpgradeableProxy(address(clientToP2pImpl), address(clientToP2pAdmin), initData);
        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pResolvProxy(
                address(factory),
                P2P_TREASURY,
                address(checkerProxy),
                address(clientToP2pCheckerProxy),
                stUSR,
                USR,
                stRESOLV,
                RESOLV
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    function test_resolv_mainnet_usr_deposit_and_withdraw_emit_protocol_events() external {
        deal(USR, client, 100e18);

        vm.recordLogs();
        _doDeposit();
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, stUSR, ERC20_TRANSFER_EVENT);

        vm.recordLogs();
        vm.prank(client);
        P2pResolvProxy(proxyAddress).withdrawUSR(DEPOSIT_AMOUNT / 2);
        Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();
        _assertEventSeen(withdrawLogs, stUSR, ERC20_TRANSFER_EVENT);
    }

    function test_resolv_mainnet_claim_reward_tokens_emits_protocol_events() external {
        vm.createSelectFork("mainnet", 23_866_064);

        AllowedCalldataChecker checker = new AllowedCalldataChecker();
        checker.initialize();
        AllowedCalldataChecker clientToP2pChecker2 = new AllowedCalldataChecker();
        clientToP2pChecker2.initialize();

        P2pResolvProxy fresh = new P2pResolvProxy(
            address(this),
            P2P_TREASURY,
            address(checker),
            address(clientToP2pChecker2),
            stUSR,
            USR,
            stRESOLV,
            RESOLV
        );

        vm.etch(KNOWN_PROXY, address(fresh).code);

        address knownClient = makeAddr("knownClient");
        vm.prank(address(this));
        P2pResolvProxy(KNOWN_PROXY).initialize(knownClient, CLIENT_BPS);

        vm.prank(KNOWN_PROXY);
        IResolvStaking(stRESOLV).updateCheckpoint(KNOWN_PROXY);

        uint256 claimable = IResolvStaking(stRESOLV).getUserClaimableAmounts(KNOWN_PROXY, RESOLV);
        require(claimable > 0, "NO_CLAIMABLE_REWARDS");

        vm.recordLogs();
        vm.prank(knownClient);
        P2pResolvProxy(KNOWN_PROXY).claimRewardTokens();
        Vm.Log[] memory claimLogs = vm.getRecordedLogs();
        _assertEventSeen(claimLogs, RESOLV, ERC20_TRANSFER_EVENT);
    }

    function _doDeposit() private {
        bytes memory signature = _getP2pSignerSignature();

        vm.startPrank(client);
        IERC20(USR).safeApprove(proxyAddress, 0);
        IERC20(USR).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, USR, DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signature);
        vm.stopPrank();
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
}
