// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../lib/forge-std/src/Vm.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/adapters/superform/p2pSuperformProxyFactory/P2pSuperformProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import {Script} from "forge-std/Script.sol";

contract DeployOptimism is Script {
    address constant SuperformRouter = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address constant SuperPositions = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address constant P2pTreasury = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;
    address constant RewardsDistributor = 0xce23bD7205bF2B543F6B4eeC00Add0C111FEFc3B;

    function run()
    external
    returns (P2pSuperformProxyFactory factory, P2pSuperformProxy proxy)
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
        factory = new P2pSuperformProxyFactory(
            wallet.addr,
            P2pTreasury,
            SuperformRouter,
            SuperPositions,
            address(tup),
            RewardsDistributor
        );

        vm.stopBroadcast();

        proxy = P2pSuperformProxy(payable(factory.getReferenceP2pYieldProxy()));

        return (factory, proxy);
    }
}

