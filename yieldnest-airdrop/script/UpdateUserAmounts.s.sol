// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Airdrop } from "../src/Airdrop.sol";

import { BaseScript } from "script/BaseScript.s.sol";
import { BatchUpdate } from "script/BatchUpdate.sol";

import { console } from "forge-std/console.sol";

// source .env && forge script script/UpdateUserAmounts.s.sol:UpdateUserAmounts --rpc-url $HOLESKY_RPC_URL --sender
// $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT_NAME
contract UpdateUserAmounts is BaseScript, BatchUpdate {
    Airdrop public airdrop;
    uint256 public constant BATCH_SIZE = 800;

    error InvalidDeployment();

    function run() public {
        // Load user amounts from the JSON file
        _loadInput("script/inputs/season-one-eigen-holesky.json");

        address deployer = msg.sender;
        console.log("Deployer address: ", deployer);

        // Start broadcasting transactions
        vm.startBroadcast();

        // Create an instance of the Airdrop contract at the specified address
        airdrop = Airdrop(0xEedc5467f6cc6736f5A97722cc1c8382A32170c5);

        if (!airdrop.paused()) {
            airdrop.pause();
            console.log("Paused Airdrop for updating user amounts");
        }

        // Call updateUserAmounts with the loaded user amounts in batches
        updateUserAmountsInBatches(airdrop, userAmounts, BATCH_SIZE);

        airdrop.unpause();
        console.log("Unpaused Airdrop");

        // Stop broadcasting transactions
        vm.stopBroadcast();

        console.log("User amounts updated successfully for Airdrop at", address(airdrop));
    }
}
