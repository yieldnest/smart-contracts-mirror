// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "lib/yieldnest-vault/src/strategy/BaseStrategy.sol";
import {IERC20} from "lib/yieldnest-vault/src/Common.sol";
import {VaultLib} from "lib/yieldnest-vault/src/library/VaultLib.sol";
import {FeeMath} from "lib/yieldnest-vault/src/module/FeeMath.sol";
import {LinearWithdrawalFee} from "lib/yieldnest-vault/src/module/LinearWithdrawalFee.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {ERC4626WrapperLib} from "src/lib/ERC4626WrapperLib.sol";

contract ERC4626WrapperStrategy is BaseStrategy, LinearWithdrawalFee {
    string public constant ERC4626_WRAPPER_STRATEGY_VERSION = "0.1.0";

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    struct InitParams {
        address admin;
        string name;
        string symbol;
        uint8 decimals_;
        bool alwaysComputeTotalAssets_;
        uint256 defaultAssetIndex_;
        bool countNativeAsset_;
    }

    /**
     * @notice Initializes the strategy.
     * @param params The struct containing all initialization parameters.
     */
    function initialize(InitParams calldata params) external virtual initializer {
        _initialize(
            params.admin,
            params.name,
            params.symbol,
            params.decimals_,
            true, // paused
            params.countNativeAsset_,
            params.alwaysComputeTotalAssets_,
            params.defaultAssetIndex_
        );
    }

    //// FEES ////

    /**
     * @notice Returns the fee on amount where the fee would get added on top of the amount.
     * @param amount The amount on which the fee would get added.
     * @param user The address of the user.
     * @return The fee amount.
     */
    function _feeOnRaw(uint256 amount, address user) public view override returns (uint256) {
        return __feeOnRaw(amount, user);
    }

    /**
     * @notice Returns the fee amount where fee is already included in amount
     * @param amount The amount on which the fee is already included.
     * @param user The address of the user.
     * @return The fee amount.
     * @dev Calculates the fee part of an amount `amount` that already includes fees.
     * Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     */
    function _feeOnTotal(uint256 amount, address user) public view override returns (uint256) {
        return __feeOnTotal(amount, user);
    }

    // //// FEES ADMIN ////

    /**
     * @notice Sets the base withdrawal fee for the vault
     * @param baseWithdrawalFee_ The new base withdrawal fee in basis points (1/10000)
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function setBaseWithdrawalFee(uint64 baseWithdrawalFee_) external virtual onlyRole(FEE_MANAGER_ROLE) {
        _setBaseWithdrawalFee(baseWithdrawalFee_);
    }

    /**
     * @notice Sets whether the withdrawal fee is exempted for a user
     * @param user_ The address of the user
     * @param baseWithdrawalFee_ The overridden base withdrawal fee in basis points (1/10000)
     * @param toOverride_ Whether to override the withdrawal fee for the user
     * @dev Only callable by accounts with FEE_MANAGER_ROLE
     */
    function overrideBaseWithdrawalFee(address user_, uint64 baseWithdrawalFee_, bool toOverride_)
        external
        virtual
        onlyRole(FEE_MANAGER_ROLE)
    {
        _overrideBaseWithdrawalFee(user_, baseWithdrawalFee_, toOverride_);
    }

    //// ASSETS ////

    /**
     * @notice Returns the available assets for the strategy. for the base asset
     * it includes the balance of the underlying asset and the balance of the vault.
     * @param asset_ The asset to check.
     * @return availableAssets The available assets.
     */
    function _availableAssets(address asset_) internal view virtual override returns (uint256 availableAssets) {
        if (asset_ == asset()) {
            availableAssets = ERC4626WrapperLib.availableAssets(this, asset_);
        } else {
            availableAssets = super._availableAssets(asset_);
        }
    }
}
