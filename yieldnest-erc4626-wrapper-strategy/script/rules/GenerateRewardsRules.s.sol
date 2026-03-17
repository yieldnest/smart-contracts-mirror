// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "forge-std/console.sol";
import {SafeRules, IVault} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {StakeDaoRules} from "script/rules/StakeDaoRules.sol";
import {ERC20Rules} from "script/rules/ERC20Rules.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract GenerateRewardsRules is Script {
    function promptAddress(string memory prompt) public returns (address) {
        string memory addressInput = vm.prompt(prompt);
        require(bytes(addressInput).length > 0, "Address input cannot be empty");
        return vm.parseAddress(addressInput);
    }

    function run() public virtual {
        // Take CRV token and accountant directly from contracts
        address stakedaoAccountant = MC.STAKEDAO_ACCOUNTANT;
        address crvToken = MC.CRV;

        // Only prompt for rewards receiver
        address rewardsReceiver = promptAddress("Enter the Rewards Receiver address:");

        // Generate the rules
        SafeRules.RuleParams memory claimRule = StakeDaoRules.getAccountantClaimRule(stakedaoAccountant);
        SafeRules.RuleParams memory crvTransferRule = ERC20Rules.getTransferRule(crvToken, rewardsReceiver);

        // Prepare arrays for setProcessorRules
        address[] memory targets = new address[](2);
        bytes4[] memory functionSigs = new bytes4[](2);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](2);

        targets[0] = claimRule.contractAddress;
        targets[1] = crvTransferRule.contractAddress;
        functionSigs[0] = claimRule.funcSig;
        functionSigs[1] = crvTransferRule.funcSig;
        rules[0] = claimRule.rule;
        rules[1] = crvTransferRule.rule;

        // Generate calldata for setProcessorRules
        // Assumes you have a 'vault' reference with setProcessorRules defined
        // setProcessorRules(address[] targets, bytes4[] functionSigs, bytes[] rules)
        bytes memory setProcessorRulesCall = abi.encodeWithSelector(
            // Replace 'VaultInterface' with your actual vault contract interface import.
            // E.g. IVault(address(0)).setProcessorRules.selector, ...
            IVault.setProcessorRules.selector,
            targets,
            functionSigs,
            rules
        );

        console.log("STAK:", MC.STAK);

        // Print out the encoded setProcessorRules call
        console.log("setProcessorRules calldata:");
        console.logBytes(setProcessorRulesCall);
    }
}
