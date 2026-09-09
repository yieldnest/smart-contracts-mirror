// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IAccountingTokenFactory {
    function deployAccountingTokenImplementation(address trackedAsset) external returns (address);
}
