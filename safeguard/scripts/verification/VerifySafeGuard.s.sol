// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SafeGuard} from "src/SafeGuard.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {BaseScript} from "scripts/BaseScript.s.sol";

// To run this script:
// forge script scripts/verification/VerifySafeGuard.s.sol --sig "run(string calldata)" \
// "deployments/my-deployment-1.json" --rpc-url https://rpc.ankr.com/eth_holesky
/**
 * @title VerifySafeGuard
 * @notice Script to verify a SafeGuard deployment is configured correctly
 * @dev Takes deployment JSON path as parameter and verifies:
 *      - TUP ownership (proxy admin relationship)
 *      - Roles (DEFAULT_ADMIN_ROLE, PROCESSOR_MANAGER_ROLE)
 *      - Proxy/ProxyAdmin relationship
 *      - Timelock configuration
 */
contract VerifySafeGuard is BaseScript, Test {

    /**
     * @notice Verify a SafeGuard deployment
     * @param _deploymentPath Path to the deployment JSON file (e.g., "deployments/my-deployment-1.json")
     */
    function run(string calldata _deploymentPath) external {
        _loadDeploymentFromPath(_deploymentPath);

        console.log("");
        console.log("=== Starting SafeGuard Verification ===");
        console.log("");

        // ============================================
        // Proxy / ProxyAdmin Relationship Verification
        // ============================================
        console.log("--- Proxy Configuration ---");

        // Assert that the proxy admin is correctly set
        address actualProxyAdmin = ProxyUtils.getProxyAdmin(address(safeguard));
        assertEq(actualProxyAdmin, address(proxyAdmin), "Proxy admin is not set correctly");
        console.log("[PASS] Proxy admin correctly set to:", address(proxyAdmin));

        // Assert that the implementation is correctly set
        address actualImplementation = ProxyUtils.getImplementation(address(safeguard));
        assertEq(actualImplementation, address(implementation), "Implementation is not set correctly");
        console.log("[PASS] Implementation correctly set to:", address(implementation));

        // ============================================
        // TUP Ownership Verification
        // ============================================
        console.log("");
        console.log("--- TUP Ownership ---");

        // Assert that the timelock is the owner of the proxy admin
        address proxyAdminOwner = ProxyAdmin(proxyAdmin).owner();
        assertEq(proxyAdminOwner, address(timelock), "Timelock is not the owner of the proxy admin");
        console.log("[PASS] Timelock is the owner of the ProxyAdmin");
        console.log("       ProxyAdmin owner:", proxyAdminOwner);

        // ============================================
        // SafeGuard Roles Verification
        // ============================================
        console.log("");
        console.log("--- SafeGuard Roles ---");

        // Assert that the admin has DEFAULT_ADMIN_ROLE
        assertTrue(safeguard.hasRole(safeguard.DEFAULT_ADMIN_ROLE(), admin), "Admin does not have DEFAULT_ADMIN_ROLE");
        console.log("[PASS] Admin has DEFAULT_ADMIN_ROLE");

        // Assert that the admin has PROCESSOR_MANAGER_ROLE
        assertTrue(safeguard.hasRole(safeguard.PROCESSOR_MANAGER_ROLE(), admin), "Admin does not have PROCESSOR_MANAGER_ROLE");
        console.log("[PASS] Admin has PROCESSOR_MANAGER_ROLE");

        // Assert that the admin has GUARD_ADMIN_ROLE
        assertTrue(safeguard.hasRole(safeguard.GUARD_ADMIN_ROLE(), admin), "Admin does not have GUARD_ADMIN_ROLE");
        console.log("[PASS] Admin has GUARD_ADMIN_ROLE");

        // ============================================
        // SafeGuard Configuration Verification
        // ============================================
        console.log("");
        console.log("--- SafeGuard Configuration ---");

        // Assert that checkTransactionEnabled is true
        assertTrue(safeguard.checkTransactionEnabled(), "checkTransactionEnabled should be true");
        console.log("[PASS] checkTransactionEnabled is true");

        // Assert that checkModuleTransactionEnabled is true
        assertTrue(safeguard.checkModuleTransactionEnabled(), "checkModuleTransactionEnabled should be true");
        console.log("[PASS] checkModuleTransactionEnabled is true");

        // ============================================
        // Timelock Configuration Verification
        // ============================================
        console.log("");
        console.log("--- Timelock Configuration ---");

        // Assert that the timelock has 1 day min delay
        uint256 expectedDelay = 1 days;
        uint256 actualDelay = timelock.getMinDelay();
        assertEq(actualDelay, expectedDelay, "Timelock delay is not set to 1 day");
        console.log("[PASS] Timelock has 1 day minimum delay");
        console.log("       Delay:", actualDelay, "seconds");

        // Assert that the admin has the proposer role in the timelock
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), admin), "Admin does not have PROPOSER_ROLE in timelock");
        console.log("[PASS] Admin has PROPOSER_ROLE in timelock");

        // Assert that the admin has the executor role in the timelock
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), admin), "Admin does not have EXECUTOR_ROLE in timelock");
        console.log("[PASS] Admin has EXECUTOR_ROLE in timelock");

        // Assert that the admin has the timelock admin role
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin), "Admin does not have DEFAULT_ADMIN_ROLE in timelock");
        console.log("[PASS] Admin has DEFAULT_ADMIN_ROLE in timelock");

        // Assert that the admin has the canceller role in the timelock
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), admin), "Admin does not have CANCELLER_ROLE in timelock");
        console.log("[PASS] Admin has CANCELLER_ROLE in timelock");

        // ============================================
        // Verify No Extra Role Holders in Timelock
        // ============================================
        console.log("");
        console.log("--- Timelock Role Exclusivity ---");

        // Verify only admin has PROPOSER_ROLE (check that address(0) doesn't have it - would mean open role)
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), address(0)), "PROPOSER_ROLE is open to anyone");
        console.log("[PASS] PROPOSER_ROLE is not open to anyone");

        // Verify only admin has EXECUTOR_ROLE (check that address(0) doesn't have it - would mean open role)
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "EXECUTOR_ROLE is open to anyone");
        console.log("[PASS] EXECUTOR_ROLE is not open to anyone");

        // ============================================
        // Summary
        // ============================================
        console.log("");
        console.log("=== Verification Complete ===");
        console.log("All checks passed!");
        console.log("");
        console.log("Summary:");
        console.log("  Name:", name);
        console.log("  Admin:", admin);
        console.log("  Proxy:", address(safeguard));
        console.log("  Implementation:", address(implementation));
        console.log("  ProxyAdmin:", address(proxyAdmin));
        console.log("  Timelock:", address(timelock));
    }
}
