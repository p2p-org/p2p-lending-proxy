// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../src/adapters/ethena/p2pEthenaProxy/P2pEthenaProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetProtocolEvents is Test {
    using SafeERC20 for IERC20;

    address constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant P2P_TREASURY = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant SIG_DEADLINE = 1_734_464_723;
    uint256 constant DEPOSIT_AMOUNT = 10 ether;
    bytes32 private constant ERC4626_DEPOSIT_EVENT = keccak256("Deposit(address,address,uint256,uint256)");
    bytes32 private constant ERC20_TRANSFER_EVENT = keccak256("Transfer(address,address,uint256)");

    P2pYieldProxyFactory private factory;
    address private client;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    function setUp() public {
        vm.createSelectFork("mainnet", 21_308_893);

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
        referenceProxy = address(new P2pEthenaProxy(address(factory), P2P_TREASURY, address(checkerProxy), address(clientToP2pCheckerProxy), SUSDE, USDE));
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
    }

    function test_ethena_mainnet_deposit_cooldown_claim_emits_protocol_events() external {
        deal(USDE, client, 100e18);

        vm.recordLogs();
        _doDeposit();
        Vm.Log[] memory depositLogs = vm.getRecordedLogs();
        _assertEventSeen(depositLogs, SUSDE, ERC4626_DEPOSIT_EVENT);

        uint256 shares = IERC20(SUSDE).balanceOf(proxyAddress);
        assertGt(shares, 0);

        vm.recordLogs();
        vm.prank(client);
        P2pEthenaProxy(proxyAddress).cooldownShares(shares / 2);
        Vm.Log[] memory cooldownLogs = vm.getRecordedLogs();
        _assertEventSeen(cooldownLogs, SUSDE, ERC20_TRANSFER_EVENT);

        _forward(10_000 * 7);

        vm.recordLogs();
        vm.prank(client);
        P2pEthenaProxy(proxyAddress).withdrawAfterCooldown();
        Vm.Log[] memory claimLogs = vm.getRecordedLogs();
        _assertEventSeen(claimLogs, USDE, ERC20_TRANSFER_EVENT);
    }

    function _doDeposit() private {
        bytes memory signature = _getP2pSignerSignature();

        vm.startPrank(client);
        IERC20(USDE).safeApprove(proxyAddress, 0);
        IERC20(USDE).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, USDE, DEPOSIT_AMOUNT, CLIENT_BPS, SIG_DEADLINE, signature);
        vm.stopPrank();
    }

    function _getP2pSignerSignature() private view returns (bytes memory) {
        bytes32 hashForSigner = factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, SIG_DEADLINE);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _forward(uint256 _blocks) private {
        vm.roll(block.number + _blocks);
        vm.warp(block.timestamp + _blocks * 13);
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
