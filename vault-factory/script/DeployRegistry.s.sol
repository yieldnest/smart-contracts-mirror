// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {TimelockDeployer} from "src/lib/TimelockDeployer.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";

contract DeployRegistry is Script {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external returns (Registry implementation, TimelockController timelock, IRegistry registry) {
        address admin = vm.promptAddress("Registry admin (timelock proposer/executor)");
        uint256 minDelay = vm.promptUint("Timelock min delay in seconds");

        require(admin != address(0), "admin");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        implementation = new Registry();
        timelock = TimelockDeployer.deployInline(admin, minDelay);

        // The deployer owns the registry just long enough to register the implementation
        // addresses; ownership moves to the timelock before the broadcast ends.
        bytes memory initData = abi.encodeCall(IRegistry.initialize, (deployer));
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);
        registry = IRegistry(address(proxy));

        registry.setValues(_keys(), _values());
        registry.transferOwnership(address(timelock));

        vm.stopBroadcast();

        require(registry.owner() == address(timelock), "owner not timelock");
        require(registry.valueOf(RegistryKeys.VAULT) == RegistryImplementations.VAULT_IMPLEMENTATION, "vault key");

        address proxyAdmin = _proxyAdmin(address(registry));

        console2.log("Registry implementation:", address(implementation));
        console2.log("Registry proxy:", address(registry));
        console2.log("Registry proxy admin:", proxyAdmin);
        console2.log("Registry timelock:", address(timelock));
        console2.log("Registry owner:", registry.owner());

        string memory obj = "deployment";
        vm.serializeAddress(obj, "registryImplementation", address(implementation));
        vm.serializeAddress(obj, "registryProxyAdmin", proxyAdmin);
        vm.serializeAddress(obj, "registryTimelock", address(timelock));
        string memory json = vm.serializeAddress(obj, "registry", address(registry));

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/registry-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment written to:", path);
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }

    function _keys() internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](6);
        keys[0] = RegistryKeys.VAULT;
        keys[1] = RegistryKeys.WRAPPED_TOKEN;
        keys[2] = RegistryKeys.WITHDRAWAL_REQUEST;
        keys[3] = RegistryKeys.WITHDRAWER;
        keys[4] = RegistryKeys.BAG_FACTORY;
        keys[5] = RegistryKeys.BAG;
    }

    function _values() internal pure returns (address[] memory values) {
        values = new address[](6);
        values[0] = RegistryImplementations.VAULT_IMPLEMENTATION;
        values[1] = RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION;
        values[2] = RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION;
        values[3] = RegistryImplementations.WITHDRAWER_IMPLEMENTATION;
        values[4] = RegistryImplementations.BAG_FACTORY_IMPLEMENTATION;
        values[5] = RegistryImplementations.BAG_IMPLEMENTATION;
    }
}
