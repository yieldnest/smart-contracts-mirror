// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";

library ERC4626WrapperLib {
    function availableAssets(IVault vault, address asset_) public view returns (uint256 availableAssetsAmount) {
        address[] memory assets = vault.getAssets();
        availableAssetsAmount = IERC20(asset_).balanceOf(address(vault));
        if (assets.length > 1) {
            IERC4626 targetERC4626Vault = IERC4626(assets[1]);
            // in case the second asset is available and configured is the same as
            // the base asset, we add the balance of the vault to the available assets
            // assumes it's the asset that the withdrawal hooks reference.
            if (vault.asset() == asset_) {
                availableAssetsAmount +=
                    targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)));
            }
        }
    }
}
