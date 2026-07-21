// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../src/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/adapters/erc4626/p2pErc4626Proxy/P2pErc4626Proxy.sol";
import "../../src/adapters/morpho/MorphoRewardsAllowedCalldataChecker.sol";
import "../../src/common/AllowedCalldataChecker.sol";
import "../../src/adapters/morpho/@morpho/IDistributor.sol";
import "../../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "forge-std/Test.sol";

contract MainnetMorphoClaimingMerkl is Test {

    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    address constant MERKL_REWARD_TOKEN = 0xfb48aAf5c2D5F1722C6A7910115811e7C094C9B3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PROXY_ADDRESS = 0xefB58Cf0498C04D1920B5aE60Eb0f784aA22B678;

    uint256 constant FORK_BLOCK = 23_838_815;
    uint256 constant MERKL_CLAIM_AMOUNT = 28_225_464;
    uint96 constant CLIENT_BASIS_POINTS = 8700;

    P2pYieldProxyFactory private factory;
    address private client;
    address private p2pSigner;
    address private p2pOperator;
    address private referenceProxy;

    // Checker proxies + admins for upgrades
    ProxyAdmin private opCheckerAdmin;
    TransparentUpgradeableProxy private opCheckerProxy;
    ProxyAdmin private c2pCheckerAdmin;
    TransparentUpgradeableProxy private c2pCheckerProxy;

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);
        assertEq(block.number, FORK_BLOCK);

        client = makeAddr("client");
        p2pSigner = makeAddr("p2pSigner");
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

        vm.deal(PROXY_ADDRESS, 10 ether);
        vm.deal(client, 10 ether);
        vm.deal(p2pOperator, 10 ether);
    }

    /// @dev Direct EOA Merkl claim — verifies the distributor works at this block
    function test_morpho_MorphoClaimingMerklEOA() external {
        (
            address[] memory users,
            address[] memory tokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _getMerklClaimInputs();

        uint256 usdcBefore = IERC20(USDC).balanceOf(PROXY_ADDRESS);
        uint256 claimedBefore = _getClaimedAmount();

        vm.prank(PROXY_ADDRESS);
        IDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);

        uint256 claimedAfter = _getClaimedAmount();
        uint256 usdcAfter = IERC20(USDC).balanceOf(PROXY_ADDRESS);

        assertEq(usdcAfter - usdcBefore, MERKL_CLAIM_AMOUNT);
        assertEq(claimedAfter - claimedBefore, MERKL_CLAIM_AMOUNT);
    }

    /// @dev Client claims Merkl rewards via claimAdditionalRewardTokens
    function test_morpho_MorphoClaimingMerklByClient() external {
        _deployProxy();
        _upgradeOpChecker(); // client calls → validated by operator's checker

        // Build IDistributor.claim calldata with users[0] = PROXY_ADDRESS
        (
            address[] memory users,
            address[] memory claimTokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _getMerklClaimInputs();

        bytes memory claimCalldata = abi.encodeCall(IDistributor.claim, (users, claimTokens, amounts, proofs));

        // Track USDC as payout token (Merkl converts MERKL_REWARD_TOKEN → USDC)
        address[] memory deltaTokens = new address[](1);
        deltaTokens[0] = USDC;

        uint256 clientBalanceBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalanceBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(client);
        P2pErc4626Proxy(PROXY_ADDRESS).claimAdditionalRewardTokens(MERKL_DISTRIBUTOR, claimCalldata, deltaTokens);

        uint256 clientBalanceAfter = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalanceAfter = IERC20(USDC).balanceOf(P2P_TREASURY);

        uint256 totalClaimed = (clientBalanceAfter - clientBalanceBefore) + (treasuryBalanceAfter - treasuryBalanceBefore);
        uint256 expectedP2pAmount = _expectedP2pAmount(MERKL_CLAIM_AMOUNT);
        uint256 expectedClientAmount = MERKL_CLAIM_AMOUNT - expectedP2pAmount;

        assertEq(totalClaimed, MERKL_CLAIM_AMOUNT);
        assertEq(clientBalanceAfter - clientBalanceBefore, expectedClientAmount);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedP2pAmount);
    }

    /// @dev Operator claims Merkl rewards via claimAdditionalRewardTokens
    function test_morpho_MorphoClaimingMerklByOperator() external {
        _deployProxy();
        _upgradeC2pChecker(); // operator calls → validated by client's checker

        (
            address[] memory users,
            address[] memory claimTokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _getMerklClaimInputs();

        bytes memory claimCalldata = abi.encodeCall(IDistributor.claim, (users, claimTokens, amounts, proofs));

        address[] memory deltaTokens = new address[](1);
        deltaTokens[0] = USDC;

        uint256 clientBalanceBefore = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalanceBefore = IERC20(USDC).balanceOf(P2P_TREASURY);

        vm.prank(p2pOperator);
        P2pErc4626Proxy(PROXY_ADDRESS).claimAdditionalRewardTokens(MERKL_DISTRIBUTOR, claimCalldata, deltaTokens);

        uint256 clientBalanceAfter = IERC20(USDC).balanceOf(client);
        uint256 treasuryBalanceAfter = IERC20(USDC).balanceOf(P2P_TREASURY);

        uint256 totalClaimed = (clientBalanceAfter - clientBalanceBefore) + (treasuryBalanceAfter - treasuryBalanceBefore);
        uint256 expectedP2pAmount = _expectedP2pAmount(MERKL_CLAIM_AMOUNT);
        uint256 expectedClientAmount = MERKL_CLAIM_AMOUNT - expectedP2pAmount;

        assertEq(totalClaimed, MERKL_CLAIM_AMOUNT);
        assertEq(clientBalanceAfter - clientBalanceBefore, expectedClientAmount);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedP2pAmount);
    }

    function _deployProxy() internal {
        if (PROXY_ADDRESS.code.length != 0) return;

        vm.etch(PROXY_ADDRESS, referenceProxy.code);

        vm.prank(address(factory));
        P2pErc4626Proxy(PROXY_ADDRESS).initialize(client, CLIENT_BASIS_POINTS);
    }

    function _getMerklClaimInputs()
        internal
        pure
        returns (address[] memory users, address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs)
    {
        users = new address[](1);
        users[0] = PROXY_ADDRESS;

        tokens = new address[](1);
        tokens[0] = MERKL_REWARD_TOKEN;

        amounts = new uint256[](1);
        amounts[0] = MERKL_CLAIM_AMOUNT;

        proofs = new bytes32[][](1);
        proofs[0] = _getMerklProof();
    }

    function _getMerklProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](18);
        proof[0] = 0x58835369326a1a72bf62acbafd97748693a5239d2a69caadc8f91989c6517174;
        proof[1] = 0xe09379afc254fb9f1ca57b40e8fe502d1e00ed2410bc60b61f182c7f4fdf4fce;
        proof[2] = 0x0e57e2321e5d559c2330b52c82985b21ae62731882cfb434d9286c25c360ddb5;
        proof[3] = 0x2c9b215545763bb39c7d34fc39500ba3bdedd7551d0c3cea95aabb2f912a468a;
        proof[4] = 0x6a11a222704a7a065f5b2d64e5b281b54446527ecce25418f778825f4fd60eb0;
        proof[5] = 0xbe7b6ef06c33ba8c78f56566162de0ba374677397f209a3899cf5eb71c798878;
        proof[6] = 0x8d14c70ac4039719c83bcfbec49e67987b295e54e1bd1cfe62e1e77da1e0e7d5;
        proof[7] = 0xab95e0bc834d0e1e5f6367e7fa7456dbc530b1f8bc2b443134383f5d3057b179;
        proof[8] = 0x4be43cdcbfe04cf79e0e23b61501f6df3c5548150a1e3dde405737ffccf43307;
        proof[9] = 0x4b51b26047b731e4a4fbe2165846f4ae49bb0ed97149a24d0bee432eebace689;
        proof[10] = 0xc580a1f38d7849c3d8fceffe726201b8b4204fdbc0f3fc36e9bbb3970c0adffb;
        proof[11] = 0xe1312eba87152c1ca5c00d980aa6ba87080f63448604411f407ed3eacdacdc2b;
        proof[12] = 0xcd949d463e8fcf836d1dec24a23b673b4b41da0bc7bf0b2fa093590fb69f65b6;
        proof[13] = 0x3a0985f5584800fbe626c42dfb8b301dfcafc6b92de273acba0b01147cd48094;
        proof[14] = 0x20890dda2f5bee8218fa82c2dbeabc2768965ff526050815607ccefff9060259;
        proof[15] = 0x401932a2eaf4a5835aaddc0067f9e57865a678c495760448d81ed4159c9c16a7;
        proof[16] = 0x3f9921b5362e2daa93c62ae0c6cf45b87928d4956433ee4df8454041a706244d;
        proof[17] = 0xfa2ed669b01d97babd81b8238f888c941dfdc123c7b4fde44c5981d38c4232ca;
    }

    function _expectedP2pAmount(uint256 amount) internal pure returns (uint256) {
        return (amount * (10_000 - CLIENT_BASIS_POINTS) + 9999) / 10_000;
    }

    function _getClaimedAmount() internal view returns (uint256) {
        (bool success, bytes memory data) = MERKL_DISTRIBUTOR.staticcall(
            abi.encodeWithSignature("claimed(address,address)", PROXY_ADDRESS, MERKL_REWARD_TOKEN)
        );
        require(success, "claimed read failed");
        (uint208 amount,,) = abi.decode(data, (uint208, uint48, bytes32));
        return uint256(amount);
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
