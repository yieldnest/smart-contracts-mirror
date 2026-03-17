// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";

contract SingleAssetProvider {
    error UnsupportedAsset(address asset);

    address public immutable underlyingAsset;
    uint256 public immutable unitValue;

    constructor(address asset, uint256 unitValue_) {
        underlyingAsset = asset;
        unitValue = unitValue_;
    }

    function getRate(address asset) external view returns (uint256) {
        if (asset == underlyingAsset) {
            return unitValue;
        } else {
            revert UnsupportedAsset(asset);
        }
    }
}
