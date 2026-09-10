// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Safe} from "lib/safeguard/lib/safe-smart-account/contracts/Safe.sol";
import {Enum} from "lib/safeguard/lib/safe-smart-account/contracts/libraries/Enum.sol";
import {ISafe} from "lib/safeguard/lib/safe-smart-account/contracts/interfaces/ISafe.sol";
import {SafeProxy} from "lib/safeguard/lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "lib/safeguard/lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

library SafeTestLib {
    error SafeTransactionFailed();

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deploySingleOwnerSafe(address owner) internal returns (ISafe deployedSafe) {
        Safe singleton = new Safe();
        SafeProxyFactory safeFactory = new SafeProxyFactory();

        address[] memory owners = new address[](1);
        owners[0] = owner;

        bytes memory initializer = abi.encodeCall(
            Safe.setup, (owners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0)))
        );

        SafeProxy safeProxy = safeFactory.createProxyWithNonce(address(singleton), initializer, 0);
        deployedSafe = ISafe(address(safeProxy));
    }

    function execSingleOwnerSafeTransaction(ISafe safe, address owner, address to, bytes memory data) internal {
        execSingleOwnerSafeTransaction(safe, owner, to, 0, data, Enum.Operation.Call);
    }

    function execSingleOwnerSafeTransaction(
        ISafe safe,
        address owner,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal {
        vm.prank(owner);
        bool success = _exec(safe, owner, to, value, data, operation);
        if (!success) revert SafeTransactionFailed();
    }

    function _exec(ISafe safe, address owner, address to, uint256 value, bytes memory data, Enum.Operation operation)
        private
        returns (bool success)
    {
        bytes memory signature = prevalidatedOwnerSignature(owner);
        success = safe.execTransaction(to, value, data, operation, 0, 0, 0, address(0), payable(address(0)), signature);
    }

    function prevalidatedOwnerSignature(address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(uint256(uint160(owner)), uint256(0), uint8(1));
    }
}
