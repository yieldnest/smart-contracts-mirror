// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {WrappedTokenTestBase} from "./WrappedTokenTestBase.sol";

contract WrappedTokenTest_18Decimals_Underlying is WrappedTokenTestBase {
    function underlyingDecimals() public pure override returns (uint8) {
        return 18;
    }
}
