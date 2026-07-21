// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../lib/forge-std/src/Vm.sol";
import "../lib/forge-std/src/console2.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/adapters/superform/p2pSuperformProxy/P2pSuperformProxy.sol";
import "../src/adapters/superform/p2pSuperformProxyFactory/P2pSuperformProxyFactory.sol";
import "../src/common/AllowedCalldataChecker.sol";
import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    struct DeploymentConfig {
        address superformRouter;
        address superPositions;
        address p2pTreasury;
        address rewardsDistributor;
        address p2pSigner;
        address p2pOperator;
    }

    struct DeploymentResult {
        ProxyAdmin proxyAdmin;
        AllowedCalldataChecker allowedCalldataCheckerImplementation;
        TransparentUpgradeableProxy allowedCalldataCheckerProxy;
        P2pSuperformProxyFactory factory;
        P2pSuperformProxy referenceProxy;
    }

    bytes32 private constant SALT_PROXY_ADMIN = keccak256("p2p.superform.proxy_admin.v2");
    bytes32 private constant SALT_ALLOWED_CALLDATA_CHECKER_IMPL =
        keccak256("p2p.superform.allowed_calldata_checker.impl.v2");
    bytes32 private constant SALT_ALLOWED_CALLDATA_CHECKER_PROXY =
        keccak256("p2p.superform.allowed_calldata_checker.proxy.v2");
    bytes32 private constant SALT_FACTORY = keccak256("p2p.superform.proxy_factory.v2");

    address private constant DEFAULT_SUPERFORM_ROUTER = 0xa195608C2306A26f727d5199D5A382a4508308DA;
    address private constant DEFAULT_SUPER_POSITIONS = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
    address private constant DEFAULT_P2P_TREASURY = 0x641ca805C75cC5D1ffa78C0181Aba1F77BD17904;
    address private constant DEFAULT_REWARDS_DISTRIBUTOR = 0xce23bD7205bF2B543F6B4eeC00Add0C111FEFc3B;

    function run() external returns (DeploymentResult memory deployment) {
        DeploymentConfig memory config = _loadConfig();
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        config.p2pSigner = vm.envOr("P2P_SIGNER", deployer);
        config.p2pOperator = vm.envOr("P2P_OPERATOR", config.p2pSigner);

        console2.log("Deploying with signer:", config.p2pSigner);
        console2.log("Using operator:", config.p2pOperator);
        console2.log("Broadcast sender:", deployer);
        console2.log("Target chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = _deployProxyAdmin(deployer);
        AllowedCalldataChecker allowedImplementation = _deployAllowedCalldataChecker(deployer);
        TransparentUpgradeableProxy allowedProxy =
            _deployAllowedCalldataCheckerProxy(deployer, proxyAdmin, allowedImplementation);
        P2pSuperformProxyFactory factory = _deployFactory(deployer, config, address(allowedProxy));

        vm.stopBroadcast();

        P2pSuperformProxy referenceProxy = P2pSuperformProxy(payable(factory.getReferenceP2pYieldProxy()));

        console2.log("ProxyAdmin:", address(proxyAdmin));
        console2.log("AllowedCalldataChecker implementation:", address(allowedImplementation));
        console2.log("AllowedCalldataChecker proxy:", address(allowedProxy));
        console2.log("P2pSuperformProxyFactory:", address(factory));
        console2.log("Reference P2pSuperformProxy:", address(referenceProxy));

        deployment = DeploymentResult({
            proxyAdmin: proxyAdmin,
            allowedCalldataCheckerImplementation: allowedImplementation,
            allowedCalldataCheckerProxy: allowedProxy,
            factory: factory,
            referenceProxy: referenceProxy
        });
    }

    function _loadConfig() private view returns (DeploymentConfig memory config) {
        address router = vm.envOr("SUPERFORM_ROUTER", DEFAULT_SUPERFORM_ROUTER);
        address superPositions = vm.envOr("SUPER_POSITIONS", DEFAULT_SUPER_POSITIONS);
        address treasury = vm.envOr("P2P_TREASURY", DEFAULT_P2P_TREASURY);
        address rewards = vm.envOr("REWARDS_DISTRIBUTOR", DEFAULT_REWARDS_DISTRIBUTOR);

        config.superformRouter = router;
        config.superPositions = superPositions;
        config.p2pTreasury = treasury;
        config.rewardsDistributor = rewards;
    }

    function _deployProxyAdmin(address deployer) private returns (ProxyAdmin proxyAdmin) {
        bytes memory bytecode = type(ProxyAdmin).creationCode;
        address predicted = vm.computeCreate2Address(SALT_PROXY_ADMIN, keccak256(bytecode), deployer);

        if (predicted.code.length == 0) {
            proxyAdmin = new ProxyAdmin{salt: SALT_PROXY_ADMIN}();
        } else {
            proxyAdmin = ProxyAdmin(predicted);
        }
    }

    function _deployAllowedCalldataChecker(address deployer)
        private
        returns (AllowedCalldataChecker allowedCalldataChecker)
    {
        bytes memory bytecode = type(AllowedCalldataChecker).creationCode;
        address predicted = vm.computeCreate2Address(SALT_ALLOWED_CALLDATA_CHECKER_IMPL, keccak256(bytecode), deployer);

        if (predicted.code.length == 0) {
            allowedCalldataChecker = new AllowedCalldataChecker{salt: SALT_ALLOWED_CALLDATA_CHECKER_IMPL}();
        } else {
            allowedCalldataChecker = AllowedCalldataChecker(predicted);
        }
    }

    function _deployAllowedCalldataCheckerProxy(
        address deployer,
        ProxyAdmin proxyAdmin,
        AllowedCalldataChecker implementation
    ) private returns (TransparentUpgradeableProxy proxy) {
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(address(implementation), address(proxyAdmin), initData)
        );
        address predicted = vm.computeCreate2Address(SALT_ALLOWED_CALLDATA_CHECKER_PROXY, keccak256(bytecode), deployer);

        if (predicted.code.length == 0) {
            proxy = new TransparentUpgradeableProxy{salt: SALT_ALLOWED_CALLDATA_CHECKER_PROXY}(
                address(implementation), address(proxyAdmin), initData
            );
        } else {
            proxy = TransparentUpgradeableProxy(payable(predicted));
        }
    }

    function _deployFactory(address deployer, DeploymentConfig memory config, address allowedCalldataCheckerProxy)
        private
        returns (P2pSuperformProxyFactory factory)
    {
        bytes memory bytecode = abi.encodePacked(
            type(P2pSuperformProxyFactory).creationCode,
            abi.encode(
                config.p2pSigner,
                config.p2pOperator,
                config.p2pTreasury,
                config.superformRouter,
                config.superPositions,
                allowedCalldataCheckerProxy,
                config.rewardsDistributor
            )
        );
        address predicted = vm.computeCreate2Address(SALT_FACTORY, keccak256(bytecode), deployer);

        if (predicted.code.length == 0) {
            factory = new P2pSuperformProxyFactory{salt: SALT_FACTORY}(
                config.p2pSigner,
                config.p2pOperator,
                config.p2pTreasury,
                config.superformRouter,
                config.superPositions,
                allowedCalldataCheckerProxy,
                config.rewardsDistributor
            );
        } else {
            factory = P2pSuperformProxyFactory(predicted);
        }
    }
}
