// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/// @title RegistryImplementations
/// @notice Deployed implementation addresses used to populate the registry under the
/// corresponding RegistryKeys entries.
library RegistryImplementations {
    address internal constant VAULT_IMPLEMENTATION = 0xb46D7014C1A29b6A82D8eCDE5aD29d5B09aC7A1b;
    address internal constant WRAPPED_TOKEN_IMPLEMENTATION = 0x3F574ff13a9540c3e7844704e962b1b186C31E58;
    address internal constant WITHDRAWAL_REQUEST_IMPLEMENTATION = 0x54772c665DA6f9fc2A6A37f46Ae94E2ae793d99c;
    address internal constant WITHDRAWER_IMPLEMENTATION = 0x10944CC0C2cdFF2d2cCF8ABfF755fE1e71Ce6597;
    address internal constant BAG_FACTORY_IMPLEMENTATION = 0x67c83b5E5b272655506bfcb1Cfe55995E7134261;
    address internal constant BAG_IMPLEMENTATION = 0x19d875201f7E3F89366F567B079AD0A669e436a3;
    address internal constant WITHDRAWAL_REQUEST_VIEWER = 0xb4b0F22D8854Ff7ff3FE516829305AA445b7e8d6;
}
