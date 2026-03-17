// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";

interface IMetaHooks is IHooks {
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

    function HOOK_MANAGER_ROLE() external pure returns (bytes32);

    function setHooks(address[] memory hooks_) external;
    function getHooks() external view returns (IHooks[] memory);

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
}
