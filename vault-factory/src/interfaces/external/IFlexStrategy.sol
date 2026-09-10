// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/interfaces/external/IVault.sol";

interface IFlexStrategy {
    function initialize(
        address admin,
        address accountingModuleManager,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address baseAsset,
        address accountingToken,
        bool paused_,
        address provider,
        bool alwaysComputeTotalAssets
    ) external;

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;

    function setHasAllocator(bool hasAllocators_) external;
    function setAccountingModule(address accountingModule_) external;
    function setHooks(address hooks_) external;
    function setProcessorRule(address target, bytes4 functionSig, IVault.FunctionRule calldata rule) external;
    function unpause() external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}
