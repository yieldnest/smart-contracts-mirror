// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SafeGuard} from "../src/SafeGuard.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {BaseScript} from "./BaseScript.s.sol";

// To run this script:
// forge script scripts/DeploySafeGuard.s.sol --sig "run(string,address)" \
// "my-deployment" 0xAdminAddress --rpc-url ${RPC_URL} \
// --account ${deployerAccountName} --sender ${deployer} \
// --broadcast --etherscan-api-key ${api} --verify
/**
 * @title DeploySafeGuard
 * @notice Script to deploy the SafeGuard contract with a transparent proxy and timelock controller
 * @dev Takes name and admin as CLI parameters, deploys as TransparentUpgradeableProxy,
 *      grants PROCESSOR_MANAGER_ROLE to admin, and saves deployment to JSON
 */
contract DeploySafeGuard is BaseScript {

    /**
     * @notice Deploy SafeGuard
     * @param _name The name for this deployment (used in output filename: deployments/{name}-{chainId}.json)
     * @param _admin The admin address that receives DEFAULT_ADMIN_ROLE and PROCESSOR_MANAGER_ROLE
     */
    function run(string calldata _name, address _admin) external {
        require(bytes(_name).length > 0, "Invalid name");
        require(_admin != address(0), "Invalid admin address");

        name = _name;
        admin = _admin;

        vm.startBroadcast();

        // Deploy implementation
        implementation = new SafeGuard();

        // Deploy TimelockController with 1 day delay
        address[] memory proposers = new address[](1);
        proposers[0] = _admin;
        address[] memory executors = new address[](1);
        executors[0] = _admin;
        timelock = new TimelockController(1 days, proposers, executors, _admin);

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(SafeGuard.initialize.selector, _name, _admin);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(timelock),
            initData
        );
        safeguard = SafeGuard(address(proxy));

        vm.stopBroadcast();

        // Log deployment
        console.log("=== SafeGuard Deployed ===");
        console.log("  Name:", _name);
        console.log("  Admin:", _admin);
        console.log("  Implementation:", address(implementation));
        console.log("  Proxy:", address(safeguard));
        console.log("  ProxyAdmin:", ProxyUtils.getProxyAdmin(address(safeguard)));
        console.log("  Timelock:", address(timelock));

        _saveDeployment();
    }
}
