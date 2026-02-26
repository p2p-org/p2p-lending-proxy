// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/adapters/aave/p2pAaveProxyFactory/P2pAaveProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import "../lib/forge-std/src/Vm.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    address constant P2P_TREASURY = 0x6Bb8b45a1C6eA816B70d76f83f7dC4f0f87365Ff;
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;

    function run() external returns (P2pAaveProxyFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerKey);

        vm.startBroadcast(deployerKey);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy checkerProxy =
            new TransparentUpgradeableProxy(address(implementation), address(admin), initData);

        factory = new P2pAaveProxyFactory(
            wallet.addr,
            P2P_TREASURY,
            address(checkerProxy),
            AAVE_POOL,
            AAVE_DATA_PROVIDER
        );
        vm.stopBroadcast();
    }
}
