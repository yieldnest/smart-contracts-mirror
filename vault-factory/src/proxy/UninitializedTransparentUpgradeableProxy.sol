// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UninitializedTransparentUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(address logic, address initialOwner) TransparentUpgradeableProxy(logic, initialOwner, "") {}

    function _unsafeAllowUninitialized() internal pure override returns (bool) {
        return true;
    }
}
