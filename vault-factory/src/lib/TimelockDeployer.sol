// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title TimelockDeployer
/// @notice Deploys the per-vault TimelockController.
/// @dev External library so the TimelockController creation code lives in the deployed library
/// instead of the factory bytecode, keeping the factory under the EIP-170 size limit. The
/// delegatecall runs CREATE in the factory's context, so the timelock's deployer is still the
/// factory.
library TimelockDeployer {
    function deploy(address admin, uint256 timelockDuration) external returns (TimelockController) {
        return deployInline(admin, timelockDuration);
    }

    /// @dev For forge scripts, which must use this internal (inlined) variant: a CREATE inside a
    /// delegatecalled library is silently dropped from the broadcast, so the external `deploy`
    /// would report success without ever deploying the timelock on-chain.
    function deployInline(address admin, uint256 timelockDuration) internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory executors = new address[](1);
        executors[0] = admin;

        // The admin also receives the timelock's DEFAULT_ADMIN_ROLE. Role grants and revokes are
        // immediate calls, not timelocked operations, so the admin can rewire the proposer,
        // executor, and canceller sets (or hand off / renounce timelock control) without waiting
        // out the delay. The delay only protects scheduled operations - upgrades, provider and
        // asset changes - not the timelock's own membership. This trades the self-administered
        // hardening OZ recommends for direct recoverability by the vault admin.
        return new TimelockController(timelockDuration, proposers, executors, admin);
    }
}
