// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IWithdrawer {
    function initialize(address token_, address withdrawalRequest_) external;
}
