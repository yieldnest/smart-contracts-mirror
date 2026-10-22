// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IRewardsSweeper {
    function initialize(address admin, address accountingModuleManager, address accountingModule_) external;

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
}
