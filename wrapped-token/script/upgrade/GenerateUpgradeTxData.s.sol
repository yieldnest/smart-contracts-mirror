// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract GenerateUpgradeTxData is Script {
    address constant WUSDC_PROXY = 0xdA7d2025c7f1f1A1d34AB3F4dF01102d0428E574;
    address constant WUSDC_PROXY_ADMIN = 0x6461205616F55f01523183617c5AeC818415417b;

    function run() external {
        // You need to replace this with the actual new implementation address
        address newImplementation = vm.envAddress("NEW_IMPLEMENTATION");

        // Generate upgrade calldata
        bytes memory upgradeCalldata =
            abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", WUSDC_PROXY, newImplementation, "");

        console.log("=== UPGRADE TRANSACTION DATA ===");
        console.log("Target (ProxyAdmin):", WUSDC_PROXY_ADMIN);
        console.log("Proxy to upgrade:", WUSDC_PROXY);
        console.log("New implementation:", newImplementation);
        console.log("Calldata:");
        console.logBytes(upgradeCalldata);
        console.log("Calldata (hex):");
        console.log(vm.toString(upgradeCalldata));
    }
}
