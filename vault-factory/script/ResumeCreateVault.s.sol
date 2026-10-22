// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";

contract ResumeCreateVault is Script {
    /// @notice Ethereum mainnet USDC, used as both base and default asset.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6; // 1 USDC

    function run() external returns (IVaultFactory.CreatedVault memory created) {
        address factory = vm.promptAddress("VaultFactory address");
        bytes32 deploymentId = vm.parseBytes32(vm.prompt("Deployment id"));
        uint256 bootstrapMultiplier = vm.promptUint("Bootstrap count (1 without flex, 2 with flex)");

        vm.startBroadcast();
        IERC20(USDC).approve(factory, BOOTSTRAP_AMOUNT * bootstrapMultiplier);
        created = IVaultFactory(factory).resumeCreateVault(deploymentId);
        vm.stopBroadcast();

        console2.log("Vault:", created.vault);
        console2.log("Timelock:", created.timelock);
        console2.log("Wrapped token:", created.wrappedToken);
        console2.log("Provider:", created.provider);
        console2.log("Withdrawal request:", created.withdrawalRequest);
        console2.log("Withdrawer:", created.withdrawer);
        console2.log("Bag factory:", created.bagFactory);
        console2.log("Request policy:", created.requestPolicy);
        console2.log("SafeGuard:", created.safeGuard);
        console2.log("Accounting module hook:", created.accountingModuleHook);
        console2.log("Flex strategy:", created.flexStrategy);
        console2.log("Accounting token:", created.accountingToken);
        console2.log("Accounting module:", created.accountingModule);
        console2.log("Rewards sweeper:", created.rewardsSweeper);
    }
}
