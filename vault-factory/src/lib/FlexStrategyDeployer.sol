// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IAccountingModule} from "src/interfaces/external/IAccountingModule.sol";
import {IAccountingToken} from "src/interfaces/external/IAccountingToken.sol";
import {IAccountingTokenFactory} from "src/interfaces/external/IAccountingTokenFactory.sol";
import {IFlexStrategy} from "src/interfaces/external/IFlexStrategy.sol";
import {IHooksDeployer} from "src/interfaces/external/IHooksDeployer.sol";
import {IRewardsSweeper} from "src/interfaces/external/IRewardsSweeper.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {FixedRateProvider} from "src/provider/FixedRateProvider.sol";
import {FlexProvider} from "src/provider/FlexProvider.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";

/// @title FlexStrategyDeployer
/// @notice Deploys and wires the flex strategy system for a vault, mirroring the upstream
/// yieldnest-flex-strategy FlexStrategyDeployer minus SafeGuard deployment.
/// @dev External library so the deployment logic and embedded creation code live outside the
/// factory bytecode. The delegatecall runs in the factory's context: the factory is the temporary
/// admin during wiring and renounces everything except the strategy ALLOCATOR_ROLE, which the
/// factory keeps until it performs the strategy bootstrap deposit.
library FlexStrategyDeployer {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 internal constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 internal constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 internal constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 internal constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 internal constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");
    bytes32 internal constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");
    bytes32 internal constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 internal constant REWARDS_PROCESSOR_ROLE = keccak256("REWARDS_PROCESSOR_ROLE");
    bytes32 internal constant LOSS_PROCESSOR_ROLE = keccak256("LOSS_PROCESSOR_ROLE");
    bytes32 internal constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");
    bytes32 internal constant SNAPSHOT_REWARDS_SWEEPER_ROLE = keccak256("SNAPSHOT_REWARDS_SWEEPER_ROLE");

    uint16 internal constant ACCOUNTING_COOLDOWN_SECONDS = 1 hours;

    struct Config {
        address vault;
        address effectiveBaseAsset;
        address timelock;
        address baseAsset;
        uint8 baseAssetDecimals;
        bool alwaysComputeTotalAssets;
        bool deployRewardsSweeper;
        address processor;
        address pauser;
        address unpauser;
        // implementations resolved from the registry; rewardsSweeperLogic is only set (and only
        // required) when deployRewardsSweeper is true
        address strategyLogic;
        address accountingModuleLogic;
        address accountingTokenFactory;
        address rewardsSweeperLogic;
        address hooksDeployer;
        // flex parameters
        address safe;
        address accountingProcessor;
        uint256 targetApy;
        uint256 lowerBound;
        uint256 minRewardableAssets;
        string strategyName;
        string strategySymbol;
        string accountingTokenName;
        string accountingTokenSymbol;
    }

    struct FlexSystem {
        address strategy;
        address accountingToken;
        address accountingModule;
        address accountingModuleHook;
        address rewardsSweeper;
        address strategyRateProvider;
        address vaultProvider;
    }

    function deploy(Config memory cfg) external returns (FlexSystem memory sys) {
        sys = _deployContracts(cfg);
        _configureStrategy(cfg, sys);
        _configureAccountingSystem(cfg, sys);
        _renounceTemporaryRoles(sys);
    }

    /// @notice Preloads the Main Vault's processor rules for operating the strategy: approving the
    /// strategy on the default asset and deposit/mint/withdraw/redeem with the vault as the only
    /// allowed receiver and owner. The caller must hold the vault's PROCESSOR_MANAGER_ROLE.
    function configureVaultRules(address vault, address strategy, address asset) external {
        IVault target = IVault(vault);

        address[] memory strategyOnly = new address[](1);
        strategyOnly[0] = strategy;
        address[] memory vaultOnly = new address[](1);
        vaultOnly[0] = vault;

        target.setProcessorRule(
            asset, bytes4(keccak256("approve(address,uint256)")), _rule2(_addressRule(strategyOnly), _uintRule())
        );
        target.setProcessorRule(
            strategy, bytes4(keccak256("deposit(uint256,address)")), _rule2(_uintRule(), _addressRule(vaultOnly))
        );
        target.setProcessorRule(
            strategy, bytes4(keccak256("mint(uint256,address)")), _rule2(_uintRule(), _addressRule(vaultOnly))
        );
        target.setProcessorRule(
            strategy,
            bytes4(keccak256("withdraw(uint256,address,address)")),
            _rule3(_uintRule(), _addressRule(vaultOnly), _addressRule(vaultOnly))
        );
        target.setProcessorRule(
            strategy,
            bytes4(keccak256("redeem(uint256,address,address)")),
            _rule3(_uintRule(), _addressRule(vaultOnly), _addressRule(vaultOnly))
        );
    }

    function _deployContracts(Config memory cfg) internal returns (FlexSystem memory sys) {
        // Per-asset accounting token implementation, then the proxy the system actually uses.
        address accountingTokenLogic =
            IAccountingTokenFactory(cfg.accountingTokenFactory).deployAccountingTokenImplementation(cfg.baseAsset);
        sys.accountingToken = address(new UninitializedTransparentUpgradeableProxy(accountingTokenLogic, cfg.timelock));
        IAccountingToken(sys.accountingToken)
            .initialize(address(this), address(this), cfg.accountingTokenName, cfg.accountingTokenSymbol);

        sys.strategyRateProvider = address(new FixedRateProvider(sys.accountingToken));

        sys.strategy = address(new UninitializedTransparentUpgradeableProxy(cfg.strategyLogic, cfg.timelock));
        IFlexStrategy(sys.strategy)
            .initialize(
                address(this),
                address(this),
                cfg.strategyName,
                cfg.strategySymbol,
                cfg.baseAssetDecimals,
                cfg.baseAsset,
                sys.accountingToken,
                true, // initialize paused; unpaused after configuration is complete
                sys.strategyRateProvider,
                cfg.alwaysComputeTotalAssets
            );

        sys.accountingModule =
            address(new UninitializedTransparentUpgradeableProxy(cfg.accountingModuleLogic, cfg.timelock));
        IAccountingModule(sys.accountingModule)
            .initialize(
                sys.strategy,
                address(this),
                cfg.safe,
                sys.accountingToken,
                cfg.targetApy,
                cfg.lowerBound,
                cfg.minRewardableAssets,
                ACCOUNTING_COOLDOWN_SECONDS
            );

        if (cfg.deployRewardsSweeper) {
            sys.rewardsSweeper =
                address(new UninitializedTransparentUpgradeableProxy(cfg.rewardsSweeperLogic, cfg.timelock));
            IRewardsSweeper(sys.rewardsSweeper).initialize(address(this), address(this), sys.accountingModule);
        }

        sys.vaultProvider = address(new FlexProvider(cfg.effectiveBaseAsset, cfg.baseAsset, sys.strategy));
    }

    function _configureStrategy(Config memory cfg, FlexSystem memory sys) internal {
        IFlexStrategy strategy = IFlexStrategy(sys.strategy);

        // Temporary roles for wiring; renounced in _renounceTemporaryRoles. ALLOCATOR_ROLE stays
        // with the factory until the strategy bootstrap deposit is done.
        strategy.grantRole(PROCESSOR_MANAGER_ROLE, address(this));
        strategy.grantRole(ALLOCATOR_MANAGER_ROLE, address(this));
        strategy.grantRole(HOOKS_MANAGER_ROLE, address(this));
        strategy.grantRole(UNPAUSER_ROLE, address(this));
        strategy.grantRole(ALLOCATOR_ROLE, address(this));

        // Final roles: actors for operations, the vault timelock for everything critical.
        strategy.grantRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
        strategy.grantRole(PROCESSOR_ROLE, cfg.processor);
        strategy.grantRole(PAUSER_ROLE, cfg.pauser);
        strategy.grantRole(UNPAUSER_ROLE, cfg.unpauser);
        strategy.grantRole(PROVIDER_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(ASSET_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(BUFFER_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(PROCESSOR_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(ALLOCATOR_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(HOOKS_MANAGER_ROLE, cfg.timelock);
        strategy.grantRole(ACCOUNTING_MODULE_MANAGER_ROLE, cfg.timelock);

        strategy.setHasAllocator(true);
        strategy.grantRole(ALLOCATOR_ROLE, cfg.vault);

        strategy.setAccountingModule(sys.accountingModule);
        sys.accountingModuleHook =
            IHooksDeployer(cfg.hooksDeployer).deployAccountingModuleHook(sys.strategy, sys.strategy);
        strategy.setHooks(sys.accountingModuleHook);
        strategy.grantRole(PROCESSOR_ROLE, sys.accountingModuleHook);

        // The strategy's processor may only move funds through the accounting module, and
        // withdrawals may only land back on the strategy.
        address[] memory strategyOnly = new address[](1);
        strategyOnly[0] = sys.strategy;
        strategy.setProcessorRule(sys.accountingModule, bytes4(keccak256("deposit(uint256)")), _rule1(_uintRule()));
        strategy.setProcessorRule(
            sys.accountingModule,
            bytes4(keccak256("withdraw(uint256,address)")),
            _rule2(_uintRule(), _addressRule(strategyOnly))
        );

        strategy.unpause();
    }

    function _configureAccountingSystem(Config memory cfg, FlexSystem memory sys) internal {
        IAccountingToken accountingToken = IAccountingToken(sys.accountingToken);
        accountingToken.setAccountingModule(sys.accountingModule);
        accountingToken.grantRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
        accountingToken.grantRole(ACCOUNTING_MODULE_MANAGER_ROLE, cfg.timelock);

        IAccountingModule accountingModule = IAccountingModule(sys.accountingModule);
        accountingModule.grantRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
        accountingModule.grantRole(SAFE_MANAGER_ROLE, cfg.timelock);
        accountingModule.grantRole(REWARDS_PROCESSOR_ROLE, cfg.accountingProcessor);
        accountingModule.grantRole(LOSS_PROCESSOR_ROLE, cfg.safe);

        if (sys.rewardsSweeper != address(0)) {
            accountingModule.grantRole(REWARDS_PROCESSOR_ROLE, sys.rewardsSweeper);

            IRewardsSweeper rewardsSweeper = IRewardsSweeper(sys.rewardsSweeper);
            rewardsSweeper.grantRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
            rewardsSweeper.grantRole(ACCOUNTING_MODULE_MANAGER_ROLE, cfg.timelock);
            rewardsSweeper.grantRole(REWARDS_SWEEPER_ROLE, cfg.processor);
            rewardsSweeper.grantRole(SNAPSHOT_REWARDS_SWEEPER_ROLE, cfg.processor);
        }
    }

    function _renounceTemporaryRoles(FlexSystem memory sys) internal {
        IFlexStrategy strategy = IFlexStrategy(sys.strategy);
        strategy.renounceRole(PROCESSOR_MANAGER_ROLE, address(this));
        strategy.renounceRole(ALLOCATOR_MANAGER_ROLE, address(this));
        strategy.renounceRole(HOOKS_MANAGER_ROLE, address(this));
        strategy.renounceRole(UNPAUSER_ROLE, address(this));
        strategy.renounceRole(ACCOUNTING_MODULE_MANAGER_ROLE, address(this));
        strategy.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

        IAccountingToken(sys.accountingToken).renounceRole(ACCOUNTING_MODULE_MANAGER_ROLE, address(this));
        IAccountingToken(sys.accountingToken).renounceRole(DEFAULT_ADMIN_ROLE, address(this));
        IAccountingModule(sys.accountingModule).renounceRole(DEFAULT_ADMIN_ROLE, address(this));

        if (sys.rewardsSweeper != address(0)) {
            IRewardsSweeper(sys.rewardsSweeper).renounceRole(ACCOUNTING_MODULE_MANAGER_ROLE, address(this));
            IRewardsSweeper(sys.rewardsSweeper).renounceRole(DEFAULT_ADMIN_ROLE, address(this));
        }
    }

    function _uintRule() internal pure returns (IVault.ParamRule memory) {
        return IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
    }

    function _addressRule(address[] memory allowList) internal pure returns (IVault.ParamRule memory) {
        return IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
    }

    function _rule1(IVault.ParamRule memory p0) internal pure returns (IVault.FunctionRule memory rule) {
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);
        paramRules[0] = p0;
        return IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});
    }

    function _rule2(IVault.ParamRule memory p0, IVault.ParamRule memory p1)
        internal
        pure
        returns (IVault.FunctionRule memory rule)
    {
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);
        paramRules[0] = p0;
        paramRules[1] = p1;
        return IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});
    }

    function _rule3(IVault.ParamRule memory p0, IVault.ParamRule memory p1, IVault.ParamRule memory p2)
        internal
        pure
        returns (IVault.FunctionRule memory rule)
    {
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);
        paramRules[0] = p0;
        paramRules[1] = p1;
        paramRules[2] = p2;
        return IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});
    }
}
