// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ISafeGuard} from "src/interfaces/external/ISafeGuard.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";

/// @title SafeGuardDeployer
/// @notice Deploys a SafeGuard TUP and preloads the off-ramp rule expected for the flex strategy Safe.
library SafeGuardDeployer {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 internal constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");

    struct Config {
        address safeGuardLogic;
        address timelock;
        address baseAsset;
        address offRampAddress;
        string strategyName;
    }

    function deploy(Config memory cfg) external returns (address safeGuard) {
        _validateConfig(cfg);

        bytes memory initData =
            abi.encodeCall(ISafeGuard.initialize, (string.concat(cfg.strategyName, " Safeguard"), address(this)));
        safeGuard = address(new TransparentUpgradeableProxy(cfg.safeGuardLogic, cfg.timelock, initData));

        ISafeGuard guard = ISafeGuard(safeGuard);
        _configureOffRampRule(guard, cfg.baseAsset, cfg.offRampAddress);
        _grantFinalRoles(guard, cfg.timelock);
        _renounceTemporaryRoles(guard);
    }

    function _validateConfig(Config memory cfg) internal pure {
        if (
            cfg.safeGuardLogic == address(0) || cfg.timelock == address(0) || cfg.baseAsset == address(0)
                || cfg.offRampAddress == address(0)
        ) {
            revert IVaultFactory.ZeroAddress();
        }
    }

    function _configureOffRampRule(ISafeGuard safeGuard, address baseAsset, address offRampAddress) internal {
        address[] memory targets = new address[](1);
        targets[0] = baseAsset;

        bytes4[] memory functionSigs = new bytes4[](1);
        functionSigs[0] = IERC20.transfer.selector;

        ISafeGuard.FunctionRule[] memory rules = new ISafeGuard.FunctionRule[](1);
        rules[0] = _transferRule(offRampAddress);

        safeGuard.setProcessorRules(targets, functionSigs, rules);
    }

    function _grantFinalRoles(ISafeGuard safeGuard, address timelock) internal {
        safeGuard.grantRole(DEFAULT_ADMIN_ROLE, timelock);
        safeGuard.grantRole(PROCESSOR_MANAGER_ROLE, timelock);
        safeGuard.grantRole(GUARD_ADMIN_ROLE, timelock);
    }

    function _renounceTemporaryRoles(ISafeGuard safeGuard) internal {
        safeGuard.renounceRole(PROCESSOR_MANAGER_ROLE, address(this));
        safeGuard.renounceRole(GUARD_ADMIN_ROLE, address(this));
        safeGuard.renounceRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    function _transferRule(address recipient) internal pure returns (ISafeGuard.FunctionRule memory rule) {
        ISafeGuard.ParamRule[] memory paramRules = new ISafeGuard.ParamRule[](2);
        paramRules[0] = _addressRule(recipient);
        paramRules[1] = _uintRule();
        return ISafeGuard.FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});
    }

    function _addressRule(address allowed) internal pure returns (ISafeGuard.ParamRule memory rule) {
        address[] memory allowList = new address[](1);
        allowList[0] = allowed;
        return ISafeGuard.ParamRule({paramType: ISafeGuard.ParamType.ADDRESS, isArray: false, allowList: allowList});
    }

    function _uintRule() internal pure returns (ISafeGuard.ParamRule memory rule) {
        return
            ISafeGuard.ParamRule({paramType: ISafeGuard.ParamType.UINT256, isArray: false, allowList: new address[](0)});
    }
}
