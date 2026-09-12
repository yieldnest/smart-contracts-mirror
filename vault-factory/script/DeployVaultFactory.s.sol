// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {VaultFactory} from "src/VaultFactory.sol";

contract DeployVaultFactory is Script {
    function run() external returns (VaultFactory factory) {
        address registry = vm.promptAddress("Registry proxy address");

        require(registry != address(0), "registry");

        vm.startBroadcast();
        factory = new VaultFactory(IRegistry(registry));
        vm.stopBroadcast();

        console2.log("VaultFactory:", address(factory));
        console2.log("Registry:", registry);

        string memory obj = "deployment";
        vm.serializeAddress(obj, "registry", registry);
        string memory json = vm.serializeAddress(obj, "vaultFactory", address(factory));

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/vault-factory-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment written to:", path);
    }
}
