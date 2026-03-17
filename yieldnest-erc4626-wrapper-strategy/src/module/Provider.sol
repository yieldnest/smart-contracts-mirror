// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";

contract Provider {
    error UnsupportedAsset(address asset);

    address public immutable vault;
    address public immutable underlyingAsset;
    uint256 public immutable unitValue;

    constructor(address vault_, uint256 unitValue_) {
        vault = vault_;
        underlyingAsset = IERC4626(vault).asset();
        unitValue = unitValue_;
    }

    function getRate(address asset) external view returns (uint256) {
        if (asset == underlyingAsset) {
            return unitValue;
        } else if (asset == vault) {
            return IERC4626(vault).convertToAssets(unitValue);
        } else {
            revert UnsupportedAsset(asset);
        }
    }
}
