// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IBeaconProxyFactory {
    function initialize(address implementation_, address defaultAdmin, address creator, address implementationManager)
        external;
}
