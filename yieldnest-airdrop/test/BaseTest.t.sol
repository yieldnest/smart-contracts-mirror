// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/Test.sol";

contract BaseTest is Test {
    error RPCNotSet();

    address internal constant YNSAFE = 0xCCB2FEB7d8e081dcedFe1CFbefC9d46Eb383E389;
    uint256 internal constant INITIAL_BALANCE = 0;
}
