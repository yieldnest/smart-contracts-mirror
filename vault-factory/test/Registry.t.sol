// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Registry} from "src/Registry.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MinimalProxy {
    address public immutable logic;

    constructor(address logic_, bytes memory initData) {
        logic = logic_;

        if (initData.length != 0) {
            (bool success, bytes memory returnData) = logic_.delegatecall(initData);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    receive() external payable {}

    fallback() external payable {
        address logic_ = logic;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), logic_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract RegistryTest is Test {
    address private owner = address(0xA11CE);
    address private other = address(0xB0B);

    IRegistry private registry;

    function setUp() public {
        Registry registryLogic = new Registry();
        MinimalProxy proxy = new MinimalProxy(address(registryLogic), abi.encodeCall(IRegistry.initialize, (owner)));
        registry = IRegistry(address(proxy));
    }

    function testInitializeSetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function testRegistryCannotBeInitializedDirectly() public {
        Registry registryLogic = new Registry();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registryLogic.initialize(owner);
    }

    function testSetValueWithBytes32Key() public {
        bytes32 key = keccak256("VAULT_V0_4_2");
        address value = address(0x1234);

        vm.prank(owner);
        registry.setValue(key, value);

        assertEq(registry.valueOf(key), value);
    }

    function testSetValueWithStringKey() public {
        string memory key = "VAULT_V0_4_2";
        address value = address(0x1234);
        bytes32 expectedKey = keccak256(bytes(key));

        vm.prank(owner);
        registry.setValue(key, value);

        assertEq(registry.keyOf(key), expectedKey);
        assertEq(registry.valueOf(expectedKey), value);
        assertEq(registry.valueOf(key), value);
    }

    function testBulkSetValuesWithBytes32Keys() public {
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256("VAULT_V0_4_2");
        keys[1] = keccak256("FLEX_STRATEGY_V0_1_0");

        address[] memory values = new address[](2);
        values[0] = address(0x1234);
        values[1] = address(0x5678);

        vm.prank(owner);
        registry.setValues(keys, values);

        assertEq(registry.valueOf(keys[0]), values[0]);
        assertEq(registry.valueOf(keys[1]), values[1]);
    }

    function testBulkSetValuesWithStringKeys() public {
        string[] memory keys = new string[](2);
        keys[0] = "VAULT_V0_4_2";
        keys[1] = "FLEX_STRATEGY_V0_1_0";

        address[] memory values = new address[](2);
        values[0] = address(0x1234);
        values[1] = address(0x5678);

        vm.prank(owner);
        registry.setValues(keys, values);

        assertEq(registry.valueOf(keys[0]), values[0]);
        assertEq(registry.valueOf(keys[1]), values[1]);
    }

    function testOnlyOwnerCanSetValues() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IRegistry.NotOwner.selector, other));
        registry.setValue(keccak256("VAULT_V0_4_2"), address(0x1234));
    }

    function testRejectsEmptyKey() public {
        vm.prank(owner);
        vm.expectRevert(IRegistry.EmptyKey.selector);
        registry.setValue(bytes32(0), address(0x1234));
    }

    function testRejectsZeroValue() public {
        vm.prank(owner);
        vm.expectRevert(IRegistry.ZeroAddress.selector);
        registry.setValue(keccak256("VAULT_V0_4_2"), address(0));
    }

    function testRejectsMismatchedBulkArrays() public {
        bytes32[] memory keys = new bytes32[](1);
        address[] memory values = new address[](2);

        vm.prank(owner);
        vm.expectRevert(IRegistry.InvalidArrayLength.selector);
        registry.setValues(keys, values);
    }

    function testOwnerCanTransferOwnership() public {
        vm.prank(owner);
        registry.transferOwnership(other);

        assertEq(registry.owner(), other);
    }
}
