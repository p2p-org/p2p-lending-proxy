// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {
    P2pSuperformProxy,
    P2pSuperformProxy__WithdrawAmountExceedsAccrued,
    P2pSuperformProxy__NoAccruedRewards
} from "../src/adapters/superform/p2pSuperformProxy/P2pSuperformProxy.sol";
import {IP2pYieldProxyFactory} from "../src/p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import {IAllowedCalldataChecker} from "../src/common/IAllowedCalldataChecker.sol";
import "../src/adapters/superform/DataTypes.sol";
import {IBaseRouter} from "../src/adapters/superform/IBaseRouter.sol";
import {IBaseForm} from "../src/adapters/superform/IBaseForm.sol";
import {Withdrawn} from "../src/structs/P2pStructs.sol";
import {P2pYieldProxy__NotP2pOperator} from "../src/p2pYieldProxy/P2pYieldProxy.sol";

contract MockERC20 {
    string public constant name = "Mock Token";
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private s_balances;
    mapping(address => mapping(address => uint256)) private s_allowances;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address account) external view returns (uint256) {
        return s_balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = s_allowances[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) {
            s_allowances[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        s_allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return s_allowances[owner][spender];
    }

    function mint(address to, uint256 amount) external {
        s_balances[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "zero");
        uint256 balance = s_balances[from];
        require(balance >= amount, "balance");
        s_balances[from] = balance - amount;
        s_balances[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockAllowedCalldataChecker is IAllowedCalldataChecker {
    function checkCalldata(address, bytes4, bytes calldata) external pure override {}
}

contract MockRewardsDistributor {
    function batchClaim(address, uint256[] calldata, address[][] calldata, uint256[][] calldata, bytes32[][] calldata)
        external
    {}
}

contract MockFactory is IP2pYieldProxyFactory {
    address private s_operator;
    address private s_pendingOperator;

    constructor(address operator_) {
        s_operator = operator_;
    }

    function setP2pOperator(address operator_) external {
        s_operator = operator_;
    }

    function transferP2pOperator(address _newP2pOperator) external override {
        s_pendingOperator = _newP2pOperator;
    }

    function acceptP2pOperator() external override {
        s_operator = s_pendingOperator;
        s_pendingOperator = address(0);
    }

    function getPendingP2pOperator() external view override returns (address) {
        return s_pendingOperator;
    }

    function deposit(bytes calldata, uint48, uint48, uint256, bytes calldata)
        external
        payable
        override
        returns (address)
    {
        revert("MockFactory:deposit");
    }

    function predictP2pYieldProxyAddress(address, uint48, uint48) external view override returns (address) {
        return address(0);
    }

    function transferP2pSigner(address) external override {}

    function getReferenceP2pYieldProxy() external view override returns (address) {
        return address(0);
    }

    function getHashForP2pSigner(address, uint48, uint48, uint256) external view override returns (bytes32) {
        return bytes32(0);
    }

    function getP2pSigner() external view override returns (address) {
        return address(0);
    }

    function getP2pOperator() external view override returns (address) {
        return s_operator;
    }

    function getAllProxies() external view override returns (address[] memory) {
        return new address[](0);
    }

    function supportsInterface(bytes4) external pure override returns (bool) {
        return false;
    }
}

contract MockSuperPositions {
    mapping(address => mapping(uint256 => uint256)) internal s_balances;
    mapping(address => mapping(address => mapping(uint256 => uint256))) internal s_allowances;

    function setBalance(address owner, uint256 id, uint256 amount) external {
        s_balances[owner][id] = amount;
    }

    function balanceOf(address owner, uint256 id) external view returns (uint256) {
        return s_balances[owner][id];
    }

    function increaseAllowance(address spender, uint256 id, uint256 addedValue) external returns (bool) {
        s_allowances[msg.sender][spender][id] += addedValue;
        return true;
    }

    function useAllowance(address owner, address spender, uint256 id, uint256 amount) external {
        uint256 allowed = s_allowances[owner][spender][id];
        require(allowed >= amount, "allowance");
        s_allowances[owner][spender][id] = allowed - amount;

        uint256 balance = s_balances[owner][id];
        require(balance >= amount, "balance");
        s_balances[owner][id] = balance - amount;
    }
}

contract MockBaseForm {
    uint256 private s_sharePrice;

    constructor(uint256 sharePrice_) {
        s_sharePrice = sharePrice_;
    }

    function setSharePrice(uint256 sharePrice_) external {
        s_sharePrice = sharePrice_;
    }

    function previewRedeemFrom(uint256 shares_) external view returns (uint256) {
        return shares_ * s_sharePrice / 1e18;
    }

    function previewWithdrawFrom(uint256 assets_) external view returns (uint256) {
        return assets_ * 1e18 / s_sharePrice;
    }
}

contract MockYieldProtocol {
    MockSuperPositions internal immutable i_superPositions;
    MockBaseForm internal immutable i_baseForm;
    MockERC20 internal immutable i_asset;

    constructor(MockSuperPositions superPositions_, MockBaseForm baseForm_, MockERC20 asset_) {
        i_superPositions = superPositions_;
        i_baseForm = baseForm_;
        i_asset = asset_;
    }

    function singleDirectSingleVaultWithdraw(SingleDirectSingleVaultStateReq memory req_) external {
        i_superPositions.useAllowance(
            msg.sender, address(this), req_.superformData.superformId, req_.superformData.amount
        );
        uint256 assetsToSend = i_baseForm.previewRedeemFrom(req_.superformData.amount);
        require(i_asset.transfer(req_.superformData.receiverAddress, assetsToSend), "transfer failed");
    }
}

contract TestableP2pSuperformProxy is P2pSuperformProxy {
    constructor(
        address factory_,
        address treasury_,
        address router_,
        address superPositions_,
        address allowedCalldataChecker_,
        address rewardsDistributor_
    ) P2pSuperformProxy(factory_, treasury_, router_, superPositions_, allowedCalldataChecker_, rewardsDistributor_) {}

    function testSetup(address client_, uint48 depositBps_, uint48 profitBps_) external {
        s_client = payable(client_);
        s_clientBasisPointsOfDeposit = depositBps_;
        s_clientBasisPointsOfProfit = profitBps_;
    }

    function setTotals(uint256 vaultId, address asset, uint256 deposited, uint256 withdrawn) external {
        s_totalDeposited[vaultId][asset] = deposited;
        s_totalWithdrawn[vaultId][asset] =
            Withdrawn({amount: uint208(withdrawn), lastFeeCollectionTime: uint48(block.timestamp)});
    }
}

contract P2pSuperformProxyRewardsTest is Test {
    TestableP2pSuperformProxy internal proxy;
    MockFactory internal factory;
    MockSuperPositions internal superPositions;
    MockBaseForm internal baseForm;
    MockYieldProtocol internal yieldProtocol;
    MockERC20 internal assetToken;
    MockAllowedCalldataChecker internal calldataChecker;
    MockRewardsDistributor internal rewardsDistributor;

    address internal constant OPERATOR = address(0xA11CE);
    address internal constant CLIENT = address(0xB0B);
    address internal constant TREASURY = address(0xC0FFEe);

    uint256 internal constant SHARE_PRICE = 1_250_000_000_000_000_000; // 1.25 * 1e18
    uint256 internal constant INITIAL_SHARES = 100 ether;
    uint256 internal constant DEPOSIT_AMOUNT = 100 ether;
    uint256 internal constant ACCRUED_REWARDS = 25 ether;
    uint256 internal constant SHARES_FOR_REWARDS = 20 ether;

    uint256 internal vaultId;

    function setUp() public {
        assetToken = new MockERC20();
        superPositions = new MockSuperPositions();
        baseForm = new MockBaseForm(SHARE_PRICE);
        calldataChecker = new MockAllowedCalldataChecker();
        rewardsDistributor = new MockRewardsDistributor();
        factory = new MockFactory(OPERATOR);
        yieldProtocol = new MockYieldProtocol(superPositions, baseForm, assetToken);

        proxy = new TestableP2pSuperformProxy(
            address(factory),
            TREASURY,
            address(yieldProtocol),
            address(superPositions),
            address(calldataChecker),
            address(rewardsDistributor)
        );

        vaultId = uint256(uint160(address(baseForm)));

        proxy.testSetup(CLIENT, 10_000, 8_000);
        proxy.setTotals(vaultId, address(assetToken), DEPOSIT_AMOUNT, 0);

        superPositions.setBalance(address(proxy), vaultId, INITIAL_SHARES);

        assetToken.mint(address(yieldProtocol), 1_000 ether);
    }

    function test_calculateAccruedRewardsMatchesPreview() public {
        int256 rewards = proxy.calculateAccruedRewards(vaultId, address(assetToken));
        assertEq(rewards, int256(ACCRUED_REWARDS));
    }

    function test_withdrawAccruedRewards_DistributesAndResetsAccrual() public {
        bytes memory withdrawCalldata = _buildWithdrawCalldata(SHARES_FOR_REWARDS);

        vm.prank(OPERATOR);
        proxy.withdrawAccruedRewards(withdrawCalldata);

        uint256 expectedP2p = (ACCRUED_REWARDS * (10_000 - 8_000) + 9_999) / 10_000;
        uint256 expectedClient = ACCRUED_REWARDS - expectedP2p;

        assertEq(assetToken.balanceOf(TREASURY), expectedP2p, "p2p treasury amount");
        assertEq(assetToken.balanceOf(CLIENT), expectedClient, "client amount");

        int256 rewardsAfter = proxy.calculateAccruedRewards(vaultId, address(assetToken));
        assertEq(rewardsAfter, int256(0), "accrued rewards should reset");

        assertEq(
            superPositions.balanceOf(address(proxy), vaultId), INITIAL_SHARES - SHARES_FOR_REWARDS, "share balance"
        );
    }

    function test_withdrawAccruedRewards_RevertIfExceedsAccrued() public {
        uint256 excessiveShares = SHARES_FOR_REWARDS + 1 ether;
        bytes memory withdrawCalldata = _buildWithdrawCalldata(excessiveShares);

        uint256 requestedAssets = IBaseForm(address(uint160(vaultId))).previewRedeemFrom(excessiveShares);

        vm.expectRevert(
            abi.encodeWithSelector(
                P2pSuperformProxy__WithdrawAmountExceedsAccrued.selector, requestedAssets, ACCRUED_REWARDS
            )
        );
        vm.prank(OPERATOR);
        proxy.withdrawAccruedRewards(withdrawCalldata);
    }

    function test_withdrawAccruedRewards_RevertWhenNoAccruedRewards() public {
        proxy.setTotals(vaultId, address(assetToken), 125 ether, 0);

        bytes memory withdrawCalldata = _buildWithdrawCalldata(SHARES_FOR_REWARDS);

        vm.expectRevert(
            abi.encodeWithSelector(P2pSuperformProxy__NoAccruedRewards.selector, vaultId, address(assetToken))
        );
        vm.prank(OPERATOR);
        proxy.withdrawAccruedRewards(withdrawCalldata);
    }

    function test_withdrawAccruedRewards_RevertForNonOperator() public {
        bytes memory withdrawCalldata = _buildWithdrawCalldata(SHARES_FOR_REWARDS);

        address notOperator = address(0xDEAD);
        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__NotP2pOperator.selector, notOperator));
        vm.prank(notOperator);
        proxy.withdrawAccruedRewards(withdrawCalldata);
    }

    function test_doubleFeeCollectionBug_SuperformFlow() public {
        bytes memory rewardsWithdrawCalldata = _buildWithdrawCalldata(SHARES_FOR_REWARDS);

        vm.prank(OPERATOR);
        proxy.withdrawAccruedRewards(rewardsWithdrawCalldata);

        uint256 treasuryAfterRewards = assetToken.balanceOf(TREASURY);
        uint256 clientAfterRewards = assetToken.balanceOf(CLIENT);

        uint256 remainingShares = INITIAL_SHARES - SHARES_FOR_REWARDS;
        bytes memory clientWithdrawCalldata = _buildWithdrawCalldata(remainingShares);

        vm.prank(CLIENT);
        proxy.withdraw(clientWithdrawCalldata);

        uint256 clientPrincipalReceived = assetToken.balanceOf(CLIENT) - clientAfterRewards;
        uint256 treasuryGainOnPrincipal = assetToken.balanceOf(TREASURY) - treasuryAfterRewards;

        assertEq(clientPrincipalReceived, DEPOSIT_AMOUNT, "client principal received");
        assertEq(treasuryGainOnPrincipal, 0, "treasury should not earn twice");
    }

    function test_PartialWithdraw() public {
        uint256 partialShares = 10 ether;
        bytes memory withdrawCalldata = _buildWithdrawCalldata(partialShares);

        uint256 treasuryBefore = assetToken.balanceOf(TREASURY);
        uint256 clientBefore = assetToken.balanceOf(CLIENT);

        vm.prank(OPERATOR);
        proxy.withdrawAccruedRewards(withdrawCalldata);

        uint256 actualWithdrawn = baseForm.previewRedeemFrom(partialShares);
        uint256 treasuryReceived = assetToken.balanceOf(TREASURY) - treasuryBefore;
        uint256 clientReceived = assetToken.balanceOf(CLIENT) - clientBefore;

        uint256 profitBps = proxy.getClientBasisPointsOfProfit();
        uint256 expectedFee = (actualWithdrawn * (10_000 - profitBps) + 9_999) / 10_000;
        uint256 expectedClient = actualWithdrawn - expectedFee;

        uint256 treasuryDelta =
            treasuryReceived > expectedFee ? treasuryReceived - expectedFee : expectedFee - treasuryReceived;
        uint256 clientDelta =
            clientReceived > expectedClient ? clientReceived - expectedClient : expectedClient - clientReceived;

        assertLe(treasuryDelta, 1, "Treasury fee overcharged");
        assertLe(clientDelta, 1, "Client lost funds");
    }

    function _buildWithdrawCalldata(uint256 sharesToWithdraw) internal view returns (bytes memory) {
        LiqRequest memory liqRequest = LiqRequest({
            txData: "",
            token: address(assetToken),
            interimToken: address(0),
            bridgeId: 0,
            liqDstChainId: 0,
            nativeAmount: 0
        });

        SingleVaultSFData memory superformData = SingleVaultSFData({
            superformId: vaultId,
            amount: sharesToWithdraw,
            outputAmount: sharesToWithdraw,
            maxSlippage: 0,
            liqRequest: liqRequest,
            permit2data: "",
            hasDstSwap: false,
            retain4626: false,
            receiverAddress: address(proxy),
            receiverAddressSP: address(proxy),
            extraFormData: ""
        });

        SingleDirectSingleVaultStateReq memory req = SingleDirectSingleVaultStateReq({superformData: superformData});

        return abi.encodeCall(IBaseRouter.singleDirectSingleVaultWithdraw, (req));
    }
}
