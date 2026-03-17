// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {IActors} from "lib/yieldnest-vault/script/Actors.sol";

import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {SafeRules, IVault} from "@yieldnest-vault-script/rules/SafeRules.sol";
import {BaseStrategy} from "lib/yieldnest-vault/src/strategy/BaseStrategy.sol";
import {AccessControlUpgradeable} from "lib/yieldnest-vault/src/Common.sol";

library BaseRoles {
    function configureDefaultRoles(BaseStrategy strategy, address timelock, IActors actors) internal {
        // set admin roles
        strategy.grantRole(AccessControlUpgradeable(address(strategy)).DEFAULT_ADMIN_ROLE(), actors.ADMIN());
        strategy.grantRole(strategy.PROCESSOR_ROLE(), actors.PROCESSOR());
        strategy.grantRole(strategy.PAUSER_ROLE(), actors.PAUSER());
        strategy.grantRole(strategy.UNPAUSER_ROLE(), actors.UNPAUSER());

        // set timelock roles
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.ALLOCATOR_MANAGER_ROLE(), timelock);
        strategy.grantRole(strategy.HOOKS_MANAGER_ROLE(), timelock);
    }

    function configureDefaultRolesStrategy(BaseStrategy strategy, address timelock, IActors actors) internal {
        configureDefaultRoles(strategy, timelock, actors);
    }

    function configureTemporaryRoles(BaseStrategy strategy, address deployer) internal {
        strategy.grantRole(strategy.DEFAULT_ADMIN_ROLE(), deployer);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.UNPAUSER_ROLE(), deployer);
        strategy.grantRole(strategy.ALLOCATOR_MANAGER_ROLE(), deployer);
        strategy.grantRole(strategy.HOOKS_MANAGER_ROLE(), deployer);
    }

    function configureTemporaryRolesStrategy(BaseStrategy strategy, address deployer) internal {
        configureTemporaryRoles(strategy, deployer);
    }

    function renounceTemporaryRoles(BaseStrategy strategy, address deployer) internal {
        strategy.renounceRole(strategy.DEFAULT_ADMIN_ROLE(), deployer);
        strategy.renounceRole(strategy.PROCESSOR_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.BUFFER_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.PROVIDER_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.ASSET_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.UNPAUSER_ROLE(), deployer);
        strategy.renounceRole(strategy.ALLOCATOR_MANAGER_ROLE(), deployer);
        strategy.renounceRole(strategy.HOOKS_MANAGER_ROLE(), deployer);
    }

    function renounceTemporaryRolesStrategy(BaseStrategy strategy, address deployer) internal {
        renounceTemporaryRoles(strategy, deployer);
    }
}
