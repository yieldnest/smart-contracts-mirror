// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract BaseAssetProvider {
    error UnsupportedAsset(address asset);
    error ZeroAddress();

    address public immutable baseAsset;
    address public immutable defaultAsset;
    uint256 public immutable rate;

    constructor(address _baseAsset, address _defaultAsset, uint256 _rate) {
        if (_baseAsset == address(0) || _defaultAsset == address(0)) revert ZeroAddress();
        baseAsset = _baseAsset;
        defaultAsset = _defaultAsset;
        rate = _rate;
    }

    function getRate(address asset) public view returns (uint256) {
        if (asset == baseAsset || asset == defaultAsset) {
            return rate;
        }

        revert UnsupportedAsset(asset);
    }
}
