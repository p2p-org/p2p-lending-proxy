// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../../src/adapters/ethena/@ethena/IStakedUSDe.sol";
import "../../src/adapters/ethena/p2pEthenaProxy/P2pEthenaProxy.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        require(current >= amount, "ALLOWANCE");
        _allowances[from][msg.sender] = current - amount;
        _transfer(from, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "BALANCE");
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(_balances[from] >= amount, "BALANCE");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockStakedUSDe is IStakedUSDe {
    using SafeERC20 for IERC20;

    MockERC20 public immutable mockAsset;
    string public name = "Mock sUSDe";
    string public symbol = "msUSDe";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public cooldownAmounts;

    constructor(MockERC20 asset_) {
        mockAsset = asset_;
    }

    function asset() external view override returns (address) {
        return address(mockAsset);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function totalAssets() public view override returns (uint256) {
        return mockAsset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = _totalSupply;
        if (supply == 0) {
            return assets;
        }
        return assets * supply / totalAssets();
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = _totalSupply;
        if (supply == 0) {
            return shares;
        }
        return shares * totalAssets() / supply;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        shares = convertToShares(assets);
        if (shares == 0) {
            shares = assets;
        }
        IERC20(address(mockAsset)).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        assets = convertToAssets(shares);
        IERC20(address(mockAsset)).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        shares = convertToShares(assets);
        _burn(owner, shares);
        IERC20(address(mockAsset)).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        assets = convertToAssets(shares);
        _burn(owner, shares);
        IERC20(address(mockAsset)).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function cooldownAssets(uint256 assets) external override returns (uint256 shares) {
        shares = convertToShares(assets);
        _burn(msg.sender, shares);
        cooldownAmounts[msg.sender] += assets;
    }

    function cooldownShares(uint256 shares) external override returns (uint256 assets) {
        assets = convertToAssets(shares);
        _burn(msg.sender, shares);
        cooldownAmounts[msg.sender] += assets;
    }

    function unstake(address receiver) external override {
        uint256 amount = cooldownAmounts[msg.sender];
        cooldownAmounts[msg.sender] = 0;
        IERC20(address(mockAsset)).safeTransfer(receiver, amount);
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure override returns (bool) {
        revert("NON_TRANSFERABLE");
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        revert("NON_TRANSFERABLE");
    }

    function maxDeposit(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view override returns (uint256) {
        return convertToAssets(_balances[owner]);
    }

    function maxRedeem(address owner) external view override returns (uint256) {
        return _balances[owner];
    }

    function increaseYield(uint256 amount) external {
        mockAsset.mint(address(this), amount);
    }

    function _mint(address account, uint256 amount) private {
        _balances[account] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) private {
        require(_balances[account] >= amount, "BALANCE");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}

contract P2pEthenaProxyUnitTest is Test {
    using SafeERC20 for IERC20;

    MockERC20 private usde;
    MockStakedUSDe private stakedUsde;
    AllowedCalldataChecker private checker;
    P2pYieldProxyFactory private factory;
    P2pEthenaProxy private proxy;
    address private referenceProxy;

    address private client;
    uint256 private clientKey;
    address private p2pSigner;
    uint256 private p2pSignerKey;
    address private p2pOperator;
    address private treasury = address(0xBEEF);

    uint96 private constant CLIENT_BPS = 9000;
    uint256 private constant SIG_DEADLINE = 1e12;
    uint256 private constant DEPOSIT = 1_000 ether;

    function setUp() public {
        (client, clientKey) = makeAddrAndKey("client");
        (p2pSigner, p2pSignerKey) = makeAddrAndKey("signer");
        p2pOperator = makeAddr("operator");

        usde = new MockERC20("USDe", "USDE");
        stakedUsde = new MockStakedUSDe(usde);

        checker = new AllowedCalldataChecker();
        checker.initialize();
        AllowedCalldataChecker clientToP2pChecker = new AllowedCalldataChecker();
        clientToP2pChecker.initialize();

        factory = new P2pYieldProxyFactory(p2pSigner);
        referenceProxy = address(
            new P2pEthenaProxy(
                address(factory),
                treasury,
                address(checker),
                address(clientToP2pChecker),
                address(stakedUsde),
                address(usde)
            )
        );
        factory.addReferenceP2pYieldProxy(referenceProxy);

        factory.transferP2pOperator(p2pOperator);
        vm.prank(p2pOperator);
        factory.acceptP2pOperator();

        usde.mint(client, 10_000 ether);
        proxy = P2pEthenaProxy(referenceProxy);
    }

    function test_ethena_OperatorCooldownAssetsRevertsWhenNoAccrued() public {
        _clientDeposit(DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pEthenaProxy__ZeroAccruedRewards.selector);
        proxy.cooldownAssetsAccruedRewards();
    }

    function test_ethena_OperatorCooldownAssetsUsesFullAccrued() public {
        _clientDeposit(DEPOSIT);
        stakedUsde.increaseYield(120 ether);

        uint256 accrued = _positiveAccrued();
        vm.prank(p2pOperator);
        uint256 shares = proxy.cooldownAssetsAccruedRewards();

        assertGt(shares, 0, "should burn shares");
        assertEq(stakedUsde.cooldownAmounts(address(proxy)), accrued, "cooldown amount should equal accrued");
    }

    function test_ethena_OperatorWithdrawWithoutCooldownDistributesRewards() public {
        _clientDeposit(DEPOSIT);
        stakedUsde.increaseYield(200 ether);

        uint256 treasuryBefore = usde.balanceOf(treasury);
        uint256 clientBefore = usde.balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawWithoutCooldownAccruedRewards();

        uint256 treasuryAfter = usde.balanceOf(treasury);
        uint256 clientAfter = usde.balanceOf(client);

        assertGt(treasuryAfter, treasuryBefore, "treasury balance should increase");
        assertGt(clientAfter, clientBefore, "client balance should increase");
    }

    function test_ethena_OperatorWithdrawWithoutCooldownAccruedRewardsRevertsWithoutAccrued() public {
        _clientDeposit(DEPOSIT);

        vm.prank(p2pOperator);
        vm.expectRevert(P2pEthenaProxy__ZeroAccruedRewards.selector);
        proxy.withdrawWithoutCooldownAccruedRewards();
    }

    function test_ethena_DoubleFeeCollectionBug_OperatorThenClientWithdraw() public {
        _clientDeposit(DEPOSIT);
        stakedUsde.increaseYield(250 ether);

        uint256 treasuryBeforeRewards = usde.balanceOf(treasury);
        uint256 clientBeforeRewards = usde.balanceOf(client);

        vm.prank(p2pOperator);
        proxy.withdrawWithoutCooldownAccruedRewards();

        uint256 clientAfterRewards = usde.balanceOf(client);
        uint256 treasuryAfterRewards = usde.balanceOf(treasury);

        uint256 remainingShares = stakedUsde.balanceOf(address(proxy));

        vm.prank(client);
        proxy.redeemWithoutCooldown(remainingShares);

        uint256 clientPrincipalReceived = usde.balanceOf(client) - clientAfterRewards;
        uint256 treasuryPrincipalGain = usde.balanceOf(treasury) - treasuryAfterRewards;

        assertApproxEqAbs(clientPrincipalReceived, DEPOSIT, 1, "client principal received");
        assertLe(treasuryPrincipalGain, 1, "treasury gained extra");
        assertEq(proxy.getUserPrincipal(address(usde)), 0, "principal should be zero");
        assertGt(treasuryAfterRewards - treasuryBeforeRewards, 0, "treasury did not collect yield");
        assertGt(clientAfterRewards - clientBeforeRewards, 0, "client did not receive yield share");
    }

    function test_ethena_OperatorWithdrawAfterCooldownWithinAccrued() public {
        _clientDeposit(DEPOSIT);
        stakedUsde.increaseYield(150 ether);

        vm.startPrank(p2pOperator);
        proxy.cooldownAssetsAccruedRewards();

        uint256 treasuryBefore = usde.balanceOf(treasury);
        uint256 clientBefore = usde.balanceOf(client);

        proxy.withdrawAfterCooldownAccruedRewards();
        vm.stopPrank();

        uint256 treasuryAfter = usde.balanceOf(treasury);
        uint256 clientAfter = usde.balanceOf(client);

        assertGt(treasuryAfter, treasuryBefore, "treasury balance should increase");
        assertGt(clientAfter, clientBefore, "client balance should increase");
    }

    function test_ethena_OperatorWithdrawAfterCooldownRevertsWithoutAccrued() public {
        _clientDeposit(DEPOSIT);

        vm.startPrank(p2pOperator);
        vm.expectRevert(P2pEthenaProxy__ZeroAccruedRewards.selector);
        proxy.withdrawAfterCooldownAccruedRewards();
        vm.stopPrank();
    }

    function _clientDeposit(uint256 amount) private {
        address predicted = factory.predictP2pYieldProxyAddress(referenceProxy, client, CLIENT_BPS);
        bytes memory sig = _sign(client, CLIENT_BPS, SIG_DEADLINE, p2pSignerKey);

        vm.startPrank(client);
        usde.approve(predicted, type(uint256).max);
        address deployed = factory.deposit(
            referenceProxy,
            address(usde),
            amount,
            CLIENT_BPS,
            SIG_DEADLINE,
            sig
        );
        vm.stopPrank();

        proxy = P2pEthenaProxy(deployed);
    }

    function _positiveAccrued() private view returns (uint256) {
        int256 raw = proxy.calculateAccruedRewards(address(stakedUsde), address(usde));
        return raw > 0 ? uint256(raw) : 0;
    }

    function _sign(
        address _client,
        uint96 _bps,
        uint256 _deadline,
        uint256 _signerKey
    ) private view returns (bytes memory) {
        bytes32 hash = factory.getHashForP2pSigner(referenceProxy, _client, _bps, _deadline);
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, messageHash);
        return abi.encodePacked(r, s, v);
    }
}
