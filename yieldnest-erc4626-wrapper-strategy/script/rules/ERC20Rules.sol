// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";

library ERC20Rules {
    /// @notice Returns SafeRules.RuleParams for ERC20 transfer allowing only the specified receiver if set, or any if receiver is address(0)
    function getTransferRule(address contractAddress, address receiver)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("transfer(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        // Parameter 1: recipient address (respect provided receiver param)
        address[] memory recipientAllowList = new address[](receiver == address(0) ? 0 : 1);
        if (receiver != address(0)) {
            recipientAllowList[0] = receiver;
        }
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: recipientAllowList});

        // Parameter 2: amount (uint256) -- allow any
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }
}
