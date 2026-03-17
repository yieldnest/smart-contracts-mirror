// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SafeGuard} from "../src/SafeGuard.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";

/**
 * @title BaseScript
 * @notice Base script with common utilities for SafeGuard deployment and verification
 */
abstract contract BaseScript is Script {

    string public name;
    address public admin;

    TimelockController public timelock;
    SafeGuard public safeguard;
    ProxyAdmin public proxyAdmin;
    SafeGuard public implementation;

    /**
     * @notice Returns the file path for saving deployment information
     * @return The path where deployment data will be saved
     */
    function _deploymentFilePath() internal view returns (string memory) {
        return string.concat(
            "deployments/",
            name,
            "-",
            vm.toString(block.chainid),
            ".json"
        );
    }

    function _saveDeployment() internal virtual {
        string memory root = "";
        vm.serializeString(root, "name", name);
        vm.serializeAddress(root, "admin", admin);
        vm.serializeAddress(root, "safeguard-proxyAdmin", ProxyUtils.getProxyAdmin(address(safeguard)));
        vm.serializeAddress(root, "safeguard-proxy", address(safeguard));
        vm.serializeAddress(root, "safeguard-implementation", address(implementation));

        string memory jsonOutput = vm.serializeAddress(root, "timelock", address(timelock));

        vm.writeJson(jsonOutput, _deploymentFilePath());
        console.log("Deployment saved to:", _deploymentFilePath());
    }

    /**
     * @notice Load deployment from a file path
     * @param _deploymentPath The path to the deployment JSON file
     */
    function _loadDeploymentFromPath(string memory _deploymentPath) internal virtual {
        string memory json = vm.readFile(_deploymentPath);

        name = abi.decode(vm.parseJson(json, ".name"), (string));
        admin = abi.decode(vm.parseJson(json, ".admin"), (address));
        proxyAdmin = ProxyAdmin(abi.decode(vm.parseJson(json, ".safeguard-proxyAdmin"), (address)));
        safeguard = SafeGuard(abi.decode(vm.parseJson(json, ".safeguard-proxy"), (address)));
        implementation = SafeGuard(abi.decode(vm.parseJson(json, ".safeguard-implementation"), (address)));
        timelock = TimelockController(payable(abi.decode(vm.parseJson(json, ".timelock"), (address))));

        console.log("Loaded deployment from:", _deploymentPath);
        console.log("  Name:", name);
        console.log("  Admin:", admin);
        console.log("  Proxy:", address(safeguard));
        console.log("  Implementation:", address(implementation));
        console.log("  ProxyAdmin:", address(proxyAdmin));
        console.log("  Timelock:", address(timelock));
    }
}
