// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../lib/forge-std/src/Vm.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/adapters/resolv/p2pResolvProxy/P2pResolvProxy.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    address constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address constant stUSR = 0x6c8984bc7DBBeDAf4F6b2FD766f16eBB7d10AAb4;
    address constant RESOLV = 0x259338656198eC7A76c729514D3CB45Dfbf768A1;
    address constant stRESOLV = 0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23;
    address constant P2pTreasury = 0x582d37737e870bffab8360F638148B26FD1BD86b;

    function run()
        external
        returns (P2pYieldProxyFactory factory, P2pResolvProxy referenceProxy)
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
        AllowedCalldataChecker clientToP2pImpl = new AllowedCalldataChecker();
        ProxyAdmin clientToP2pAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy clientToP2pTup = new TransparentUpgradeableProxy(
            address(clientToP2pImpl),
            address(clientToP2pAdmin),
            initData
        );
        factory = new P2pYieldProxyFactory(wallet.addr);
        referenceProxy = new P2pResolvProxy(
            address(factory),
            P2pTreasury,
            address(tup),
            address(clientToP2pTup),
            stUSR,
            USR,
            stRESOLV,
            RESOLV
        );
        factory.addReferenceP2pYieldProxy(address(referenceProxy));
        vm.stopBroadcast();

        return (factory, referenceProxy);
    }
}
