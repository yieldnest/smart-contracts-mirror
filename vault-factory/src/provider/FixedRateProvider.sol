// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccountingToken} from "src/interfaces/external/IAccountingToken.sol";

/// @title FixedRateProvider
/// @notice Rate provider for the flex strategy, pricing the tracked asset and the accounting
/// token at a fixed 1:1 rate.
/// @dev Mirrors yieldnest-flex-strategy/src/FixedRateProvider.sol, vendored so the factory's
/// deployment library does not need to compile the flex strategy dependency tree.
contract FixedRateProvider {
    address public immutable ASSET;
    uint8 public immutable DECIMALS;
    address public immutable ACCOUNTING_TOKEN;

    error UnsupportedAsset(address asset);

    constructor(address accountingToken) {
        ASSET = IAccountingToken(accountingToken).TRACKED_ASSET();
        DECIMALS = IAccountingToken(accountingToken).decimals();
        ACCOUNTING_TOKEN = accountingToken;
    }

    function getRate(address asset) external view returns (uint256 rate) {
        if (asset == ASSET || asset == ACCOUNTING_TOKEN) {
            return 10 ** DECIMALS;
        }

        revert UnsupportedAsset(asset);
    }
}
