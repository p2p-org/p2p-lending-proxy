// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../lib/forge-std/src/Vm.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/adapters/ethena/p2pEthenaProxy/P2pEthenaProxy.sol";
import "../src/adapters/ethena/p2pEthenaProxyFactory/P2pEthenaProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    address constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant P2pTreasury = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;

    function run()
        external
        returns (P2pEthenaProxyFactory factory, P2pEthenaProxy proxy)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerKey);

        vm.startBroadcast(deployerKey);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy tup = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        factory = new P2pEthenaProxyFactory(
            wallet.addr,
            P2pTreasury,
            address(tup),
            sUSDe,
            USDe
        );
        vm.stopBroadcast();

        proxy = P2pEthenaProxy(factory.getReferenceP2pYieldProxy());

        return (factory, proxy);
    }
}
