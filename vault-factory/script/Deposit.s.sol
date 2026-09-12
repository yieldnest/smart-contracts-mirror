// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDepositVault {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function balanceOf(address account) external view returns (uint256);
}

contract Deposit is Script {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 amount = vm.promptUint("Deposit amount (in default asset units)");

        string memory path = string.concat("deployments/rwa-vault-", vm.toString(block.chainid), ".json");
        IDepositVault vault = IDepositVault(vm.parseJsonAddress(vm.readFile(path), ".vault"));
        IERC20 asset = IERC20(vault.asset());

        console2.log("Vault:", address(vault));
        console2.log("Default asset:", address(asset));
        console2.log("Expected shares:", vault.previewDeposit(amount));

        vm.startBroadcast();
        (, address receiver,) = vm.readCallers();

        asset.forceApprove(address(vault), amount);
        uint256 shares = vault.deposit(amount, receiver);

        vm.stopBroadcast();

        console2.log("Shares minted:", shares);
        console2.log("Share balance of", receiver, ":", vault.balanceOf(receiver));
    }
}
