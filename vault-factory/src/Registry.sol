// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRegistry} from "src/interfaces/IRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Registry is IRegistry, Initializable {
    /// @custom:storage-location erc7201:yieldnest.storage.registry
    struct RegistryStorage {
        mapping(bytes32 key => address value) values;
        address owner;
    }

    // keccak256(abi.encode(uint256(keccak256("yieldnest.storage.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RegistryStorageLocation =
        0x909b8772e0cedce76b8d912ff5053b840584f359065328fbc58590c10ef52800;

    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        if (msg.sender != _getRegistryStorage().owner) revert NotOwner(msg.sender);
        _;
    }

    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        _getRegistryStorage().owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function owner() external view returns (address) {
        return _getRegistryStorage().owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        RegistryStorage storage $ = _getRegistryStorage();
        address previousOwner = $.owner;
        $.owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function keyOf(string calldata key) external pure returns (bytes32) {
        return _keyOf(key);
    }

    function valueOf(bytes32 key) external view returns (address) {
        return _getRegistryStorage().values[key];
    }

    function valueOf(string calldata key) external view returns (address) {
        return _getRegistryStorage().values[_keyOf(key)];
    }

    function setValue(bytes32 key, address value) external onlyOwner {
        _setValue(key, value);
    }

    function setValue(string calldata key, address value) external onlyOwner {
        _setValue(_keyOf(key), value);
    }

    function setValues(bytes32[] calldata keys, address[] calldata values) external onlyOwner {
        _setValues(keys, values);
    }

    function setValues(string[] calldata keys, address[] calldata values) external onlyOwner {
        uint256 length = keys.length;
        if (length != values.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setValue(_keyOf(keys[i]), values[i]);
        }
    }

    function _setValues(bytes32[] calldata keys, address[] calldata values) internal {
        uint256 length = keys.length;
        if (length != values.length) revert InvalidArrayLength();

        for (uint256 i = 0; i < length; ++i) {
            _setValue(keys[i], values[i]);
        }
    }

    function _setValue(bytes32 key, address value) internal {
        if (key == bytes32(0)) revert EmptyKey();
        if (value == address(0)) revert ZeroAddress();

        RegistryStorage storage $ = _getRegistryStorage();
        address previousValue = $.values[key];
        $.values[key] = value;

        emit ValueUpdated(key, previousValue, value);
    }

    function _keyOf(string calldata key) internal pure returns (bytes32) {
        if (bytes(key).length == 0) revert EmptyKey();
        return keccak256(bytes(key));
    }

    function _getRegistryStorage() private pure returns (RegistryStorage storage $) {
        assembly {
            $.slot := RegistryStorageLocation
        }
    }
}
