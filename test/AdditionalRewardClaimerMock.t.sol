// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/adapters/aave/p2pAaveProxy/P2pAaveProxy.sol";
import "../src/common/AllowedCalldataChecker.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "./mock/MockAllowedCalldataChecker.sol";
import "forge-std/Test.sol";

/// @title AdditionalRewardClaimerMock
/// @notice Mock-based tests for the reverse permission mechanism (callAnyFunctionByP2pOperator)
/// and fee distribution in claimAdditionalRewardTokens.
contract AdditionalRewardClaimerMock is Test {
    using SafeERC20 for IERC20;

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint96 constant CLIENT_BPS = 8_700;
    uint256 constant DEPOSIT_AMOUNT = 10_000_000; // 10 USDC

    P2pYieldProxyFactory private factory;
    address private client;
    uint256 private p2pSignerKey;
    address private p2pSigner;
    address private p2pOperator;
    address private referenceProxy;
    address private proxyAddress;

    // Checker infrastructure — stored for upgrade
    ProxyAdmin private operatorCheckerAdmin;
    TransparentUpgradeableProxy private operatorCheckerProxy;
    ProxyAdmin private clientToP2pCheckerAdmin;
    TransparentUpgradeableProxy private clientToP2pCheckerProxy;

    function setUp() public {
        string memory mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://ethereum.publicnode.com"));
        vm.createSelectFork(mainnetRpc, 21_308_893);

        client = makeAddr("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("p2pSigner");
        p2pOperator = makeAddr("p2pOperator");

        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);

        // Operator's checker (controls what client can call)
        vm.startPrank(p2pOperator);
        AllowedCalldataChecker operatorImpl = new AllowedCalldataChecker();
        operatorCheckerAdmin = new ProxyAdmin();
        operatorCheckerProxy = new TransparentUpgradeableProxy(
            address(operatorImpl), address(operatorCheckerAdmin), initData
        );
        vm.stopPrank();

        // Client's checker (controls what p2pOperator can call)
        // ProxyAdmin owned by client
        vm.startPrank(client);
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        clientToP2pCheckerAdmin = new ProxyAdmin();
        clientToP2pCheckerProxy = new TransparentUpgradeableProxy(
            address(clientToP2pImpl), address(clientToP2pCheckerAdmin), initData
        );
        vm.stopPrank();

        vm.startPrank(p2pOperator);
        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pAaveProxy(
                address(factory),
                P2P_TREASURY,
                address(operatorCheckerProxy),
                address(clientToP2pCheckerProxy),
                AAVE_POOL,
                AAVE_DATA_PROVIDER
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);

        // Deposit to create the proxy
        deal(USDC, client, 100e6);
        _doDeposit();
    }

    /// @notice callAnyFunctionByP2pOperator reverts by default (client's checker blocks)
    function test_callAnyFunctionByP2pOperator_revertsByDefault() external {
        // Build some arbitrary calldata (e.g., ERC20.transfer)
        bytes memory callData = abi.encodeCall(IERC20.transfer, (address(0xdead), 1));

        vm.prank(p2pOperator);
        vm.expectRevert(AllowedCalldataChecker__NoAllowedCalldata.selector);
        P2pAaveProxy(proxyAddress).callAnyFunctionByP2pOperator(USDC, callData);
    }

    /// @notice After client upgrades their checker to MockAllowedCalldataChecker,
    /// p2pOperator can call through
    function test_callAnyFunctionByP2pOperator_afterClientUpgrade_succeeds() external {
        // Client upgrades their checker to allow everything
        MockAllowedCalldataChecker mockChecker = new MockAllowedCalldataChecker();
        mockChecker.initialize();

        vm.prank(client);
        clientToP2pCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)), address(mockChecker));

        // p2pOperator calls transfer on USDC (will fail on execution since proxy has no USDC balance
        // for a 0 amount transfer). Let's use a 0-amount transfer that succeeds.
        bytes memory callData = abi.encodeCall(IERC20.transfer, (address(0xdead), 0));

        vm.prank(p2pOperator);
        P2pAaveProxy(proxyAddress).callAnyFunctionByP2pOperator(USDC, callData);
    }

    /// @notice claimAdditionalRewardTokens called by p2pOperator after client's checker upgrade
    function test_claimAdditionalRewards_byP2pOperator_afterClientUpgrade() external {
        MockAllowedCalldataChecker mockChecker = new MockAllowedCalldataChecker();
        mockChecker.initialize();

        vm.prank(client);
        clientToP2pCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)), address(mockChecker));

        // Deal some reward tokens to the mock target that will "claim" to the proxy
        address mockTarget = address(new MockRewardTarget(proxyAddress));
        address rewardToken = address(new MockERC20Token("REWARD", "RWD"));
        uint256 rewardAmount = 1000e18;
        MockERC20Token(rewardToken).mint(mockTarget, rewardAmount);

        bytes memory claimCalldata = abi.encodeCall(MockRewardTarget.claimRewards, (rewardToken, rewardAmount));
        address[] memory tokens = new address[](1);
        tokens[0] = rewardToken;

        uint256 treasuryBefore = IERC20(rewardToken).balanceOf(P2P_TREASURY);
        uint256 clientBefore = IERC20(rewardToken).balanceOf(client);

        vm.prank(p2pOperator);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            mockTarget,
            claimCalldata,
            tokens
        );

        uint256 treasuryAfter = IERC20(rewardToken).balanceOf(P2P_TREASURY);
        uint256 clientAfter = IERC20(rewardToken).balanceOf(client);

        uint256 p2pGain = treasuryAfter - treasuryBefore;
        uint256 clientGain = clientAfter - clientBefore;

        assertEq(p2pGain + clientGain, rewardAmount, "total should equal reward");
        assertGt(p2pGain, 0, "p2p should receive fee");
        assertGt(clientGain, 0, "client should receive reward");
    }

    /// @notice Verify exact fee distribution matches s_clientBasisPoints
    function test_claimAdditionalRewards_feeDistribution() external {
        // Upgrade both checkers to allow everything
        MockAllowedCalldataChecker mockChecker1 = new MockAllowedCalldataChecker();
        mockChecker1.initialize();
        MockAllowedCalldataChecker mockChecker2 = new MockAllowedCalldataChecker();
        mockChecker2.initialize();

        vm.prank(p2pOperator);
        operatorCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(operatorCheckerProxy)), address(mockChecker1));
        vm.prank(client);
        clientToP2pCheckerAdmin.upgrade(ITransparentUpgradeableProxy(address(clientToP2pCheckerProxy)), address(mockChecker2));

        address mockTarget = address(new MockRewardTarget(proxyAddress));
        address rewardToken = address(new MockERC20Token("REWARD", "RWD"));
        uint256 rewardAmount = 10_000; // Use round number for easier math
        MockERC20Token(rewardToken).mint(mockTarget, rewardAmount);

        bytes memory claimCalldata = abi.encodeCall(MockRewardTarget.claimRewards, (rewardToken, rewardAmount));
        address[] memory tokens = new address[](1);
        tokens[0] = rewardToken;

        vm.prank(client);
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(
            mockTarget,
            claimCalldata,
            tokens
        );

        uint256 p2pGain = IERC20(rewardToken).balanceOf(P2P_TREASURY);
        uint256 clientGain = IERC20(rewardToken).balanceOf(client);

        // Fee = rewardAmount * (10000 - CLIENT_BPS) / 10000 = 10000 * 1300 / 10000 = 1300
        uint256 expectedP2p = rewardAmount * (10_000 - CLIENT_BPS) / 10_000;
        uint256 expectedClient = rewardAmount - expectedP2p;

        assertEq(p2pGain, expectedP2p, "p2p fee amount mismatch");
        assertEq(clientGain, expectedClient, "client amount mismatch");
        assertEq(p2pGain + clientGain, rewardAmount, "total must equal reward");
    }

    /// @notice Random address can't call claimAdditionalRewardTokens
    function test_claimAdditionalRewards_revertForNobody() external {
        address nobody = makeAddr("nobody");
        bytes memory callData = abi.encodeCall(IERC20.transfer, (address(0), 0));
        address[] memory tokens = new address[](0);

        vm.prank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(P2pYieldProxy__CallerNeitherClientNorP2pOperator.selector, nobody)
        );
        P2pAaveProxy(proxyAddress).claimAdditionalRewardTokens(USDC, callData, tokens);
    }

    // -- helpers --

    function _doDeposit() private {
        bytes memory sig = _getP2pSignerSignature();
        vm.startPrank(client);
        IERC20(USDC).safeApprove(proxyAddress, 0);
        IERC20(USDC).safeApprove(proxyAddress, type(uint256).max);
        factory.deposit(referenceProxy, USDC, DEPOSIT_AMOUNT, CLIENT_BPS, 1_734_464_723, sig);
        vm.stopPrank();
    }

    function _getP2pSignerSignature() private view returns (bytes memory) {
        bytes32 hashForSigner =
            factory.getHashForP2pSigner(referenceProxy, client, CLIENT_BPS, 1_734_464_723);
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(hashForSigner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p2pSignerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}

/// @notice Mock reward target that transfers tokens to a given proxy when claimRewards is called
contract MockRewardTarget {
    address private immutable proxy;

    constructor(address _proxy) {
        proxy = _proxy;
    }

    function claimRewards(address _token, uint256 _amount) external {
        IERC20(_token).transfer(proxy, _amount);
    }
}

/// @notice Minimal ERC20 for testing reward distribution
contract MockERC20Token is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address _to, uint256 _amount) external {
        _balances[_to] += _amount;
        totalSupply += _amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
