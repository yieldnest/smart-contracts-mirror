// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IWithdrawalRequest {
    function initialize(
        address token_,
        address defaultAdmin,
        address resolver,
        address configurationManager,
        address pauser,
        address bagFactory_,
        address withdrawer_,
        address requestPolicy_,
        uint256 maxDataLength_
    ) external;
}
