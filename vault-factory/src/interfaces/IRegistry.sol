// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IRegistry {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ValueUpdated(bytes32 indexed key, address indexed previousValue, address indexed value);

    error EmptyKey();
    error InvalidArrayLength();
    error NotOwner(address caller);
    error ZeroAddress();

    function initialize(address owner_) external;

    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;

    function keyOf(string calldata key) external pure returns (bytes32);

    function valueOf(bytes32 key) external view returns (address);

    function valueOf(string calldata key) external view returns (address);

    function setValue(bytes32 key, address value) external;

    function setValue(string calldata key, address value) external;

    function setValues(bytes32[] calldata keys, address[] calldata values) external;

    function setValues(string[] calldata keys, address[] calldata values) external;
}
