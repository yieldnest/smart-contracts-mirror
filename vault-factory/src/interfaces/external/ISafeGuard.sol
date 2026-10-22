// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ISafeGuard {
    enum ParamType {
        UINT256,
        ADDRESS
    }

    struct ParamRule {
        ParamType paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
        address validator;
    }

    function initialize(string calldata name, address admin) external;

    function grantRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address callerConfirmation) external;

    function setProcessorRules(address[] calldata target, bytes4[] calldata functionSig, FunctionRule[] calldata rule)
        external;

    function getProcessorRule(address contractAddress, bytes4 funcSig) external view returns (FunctionRule memory);
}
