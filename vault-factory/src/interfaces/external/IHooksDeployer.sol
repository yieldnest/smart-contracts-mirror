// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IHooksDeployer {
    function deployAccountingModuleHook(address vault, address flexStrategy) external returns (address);
}
