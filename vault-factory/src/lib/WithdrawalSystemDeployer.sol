// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IBeaconProxyFactory} from "src/interfaces/external/IBeaconProxyFactory.sol";
import {IWithdrawalRequest} from "src/interfaces/external/IWithdrawalRequest.sol";
import {IWithdrawer} from "src/interfaces/external/IWithdrawer.sol";
import {MinAmountRequestPolicy} from "yieldnest-vault-withdrawals/src/policies/MinAmountRequestPolicy.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";

/// @title WithdrawalSystemDeployer
/// @notice Deploys and wires the async withdrawal system for a vault.
/// @dev External library so the deployment logic and embedded creation code live outside the
/// factory bytecode. The delegatecall runs in the factory's context, so the proxies' deployer is
/// still the factory.
library WithdrawalSystemDeployer {
    struct Config {
        address vault;
        address timelock;
        address resolver;
        address pauser;
        uint256 minWithdrawalAmount;
        uint256 maxDataLength;
        // implementations resolved from the registry
        address withdrawalRequestLogic;
        address withdrawerLogic;
        address bagFactoryLogic;
        address bagLogic;
    }

    function deploy(Config memory cfg) external returns (IVaultFactory.WithdrawalSystem memory withdrawals) {
        // The withdrawal request proxy is deployed uninitialized first because the withdrawer and
        // the bag factory both need its address during their own initialization.
        withdrawals.withdrawalRequest =
            address(new UninitializedTransparentUpgradeableProxy(cfg.withdrawalRequestLogic, cfg.timelock));

        withdrawals.withdrawer =
            address(new UninitializedTransparentUpgradeableProxy(cfg.withdrawerLogic, cfg.timelock));
        IWithdrawer(withdrawals.withdrawer).initialize(cfg.vault, withdrawals.withdrawalRequest);

        withdrawals.bagFactory =
            address(new UninitializedTransparentUpgradeableProxy(cfg.bagFactoryLogic, cfg.timelock));
        IBeaconProxyFactory(withdrawals.bagFactory)
            .initialize(cfg.bagLogic, cfg.timelock, withdrawals.withdrawalRequest, cfg.timelock);

        withdrawals.requestPolicy = address(new MinAmountRequestPolicy(cfg.minWithdrawalAmount));

        IWithdrawalRequest(withdrawals.withdrawalRequest)
            .initialize(
                cfg.vault,
                cfg.timelock,
                cfg.resolver,
                cfg.timelock,
                cfg.pauser,
                withdrawals.bagFactory,
                withdrawals.withdrawer,
                withdrawals.requestPolicy,
                cfg.maxDataLength
            );
    }
}
