// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/// @title RegistryKeys
/// @notice Fixed registry keys the factory reads implementation addresses from.
/// @dev Key values are keccak256 of the human-readable string, matching Registry.keyOf. The
/// strings are namespaced as `<org>.<repo>.contracts.<source path>` of the implementation.
library RegistryKeys {
    bytes32 internal constant VAULT = keccak256("yieldnest.yieldnest-vault.contracts.src.Vault");
    bytes32 internal constant WRAPPED_TOKEN = keccak256("yieldnest.wrapped-token.contracts.src.WrappedToken");
    bytes32 internal constant WITHDRAWAL_REQUEST =
        keccak256("yieldnest.yieldnest-vault-withdrawals.contracts.src.WithdrawalRequest");
    bytes32 internal constant WITHDRAWER =
        keccak256("yieldnest.yieldnest-vault-withdrawals.contracts.src.withdrawers.BaseWithdrawer");
    bytes32 internal constant BAG_FACTORY =
        keccak256("yieldnest.yieldnest-vault-withdrawals.contracts.src.BeaconProxyFactory");
    bytes32 internal constant BAG = keccak256("yieldnest.yieldnest-vault-withdrawals.contracts.src.Bag");
}
