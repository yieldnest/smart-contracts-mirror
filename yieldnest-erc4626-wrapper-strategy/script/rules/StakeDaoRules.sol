// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";

library StakeDaoRules {
    function getDepositRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        // Only parameter: amount (uint256) -- allow any
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getWithdrawRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }

    function getAccountantClaimRule(address contractAddress) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("claim(address[],bytes[])"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: contractAddress, funcSig: funcSig, rule: rule});
    }
}
