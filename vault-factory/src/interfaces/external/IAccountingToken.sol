// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IAccountingToken {
    function initialize(address admin, address accountingModuleManager, string memory name_, string memory symbol_)
        external;

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;

    function setAccountingModule(address accountingModule_) external;

    function TRACKED_ASSET() external view returns (address);
    function decimals() external view returns (uint8);
}
