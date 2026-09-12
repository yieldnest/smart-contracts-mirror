// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {ISafeGuard} from "src/interfaces/external/ISafeGuard.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";
import {FlexProvider} from "src/provider/FlexProvider.sol";

contract VaultVerifier {
    uint8 internal constant VAULT_DECIMALS = 18;
    uint16 internal constant ACCOUNTING_COOLDOWN_SECONDS = 1 hours;
    uint256 internal constant PROVIDER_RATE = 1e18;

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
    bytes32 internal constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 internal constant ASSET_WITHDRAWER_ROLE = keccak256("ASSET_WITHDRAWER_ROLE");
    bytes32 internal constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 internal constant REWARDS_PROCESSOR_ROLE = keccak256("REWARDS_PROCESSOR_ROLE");
    bytes32 internal constant LOSS_PROCESSOR_ROLE = keccak256("LOSS_PROCESSOR_ROLE");
    bytes32 internal constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");
    bytes32 internal constant SNAPSHOT_REWARDS_SWEEPER_ROLE = keccak256("SNAPSHOT_REWARDS_SWEEPER_ROLE");
    bytes32 internal constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");
    bytes32 internal constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 internal constant CONFIGURATION_MANAGER_ROLE = keccak256("CONFIGURATION_MANAGER_ROLE");
    bytes32 internal constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 internal constant IMPLEMENTATION_MANAGER_ROLE = keccak256("IMPLEMENTATION_MANAGER_ROLE");

    struct Verification {
        address factory;
        IVaultFactory.CreatedVault created;
        IVaultFactory.VaultParams vaultParams;
        IVaultFactory.FlexStrategyParams flexParams;
    }

    error VerificationFailed(string check);

    function verify(address vault, Verification calldata verification) external view returns (bool) {
        _verify(vault == verification.created.vault, "vault mismatch");
        _verify(vault != address(0) && vault.code.length != 0, "vault code");

        uint8 baseAssetDecimals = IERC20Metadata(verification.vaultParams.baseAsset).decimals();
        address effectiveBaseAsset =
            _effectiveBaseAsset(verification.created, verification.vaultParams, baseAssetDecimals);

        _verifyVaultConfig(vault, verification, effectiveBaseAsset, baseAssetDecimals);
        _verifyProvider(verification, effectiveBaseAsset);
        _verifyWithdrawalSystem(verification);

        if (verification.flexParams.deployStrategy) {
            _verifyFlexStrategy(verification);
            _verifySafeGuard(verification);
            _verifyHooks(verification);
        } else {
            _verifyNoFlexComponents(verification.created);
        }

        return true;
    }

    function _verifyVaultConfig(
        address vaultAddress,
        Verification calldata verification,
        address effectiveBaseAsset,
        uint8 baseAssetDecimals
    ) internal view {
        IVaultView vault = IVaultView(vaultAddress);
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata params = verification.vaultParams;

        _verifyString(vault.name(), params.tokenName, "vault name");
        _verifyString(vault.symbol(), params.tokenSymbol, "vault symbol");
        _verify(vault.decimals() == VAULT_DECIMALS, "vault decimals");
        _verify(vault.asset() == params.baseAsset, "vault asset");
        _verify(vault.countNativeAsset() == params.countNativeAsset, "vault native asset");
        _verify(vault.alwaysComputeTotalAssets() == params.alwaysComputeTotalAssets, "vault accounting mode");
        _verify(vault.baseWithdrawalFee() == 0, "vault withdrawal fee");
        _verify(vault.defaultAssetIndex() == _defaultAssetIndex(baseAssetDecimals), "vault default index");
        _verify(vault.provider() == created.provider, "vault provider");
        _verify(vault.buffer() == address(0), "vault buffer");
        _verify(!vault.paused(), "vault paused");

        address[] memory assets = vault.getAssets();
        if (baseAssetDecimals == VAULT_DECIMALS) {
            _verify(assets.length == 1, "vault assets length");
            _verify(assets[0] == params.baseAsset, "vault base asset");
            _verify(created.wrappedToken == address(0), "unexpected wrapper");
        } else {
            _verify(assets.length >= 2, "vault wrapped assets length");
            _verify(assets[0] == effectiveBaseAsset, "vault wrapper asset");
            _verify(assets[1] == params.baseAsset, "vault default asset");
            _verifyWrappedToken(created.wrappedToken, params.baseAsset, baseAssetDecimals);
        }

        if (verification.flexParams.deployStrategy) {
            _verify(assets.length == (baseAssetDecimals == VAULT_DECIMALS ? 2 : 3), "vault flex assets length");
            _verify(assets[assets.length - 1] == created.flexStrategy, "vault strategy asset");
            _verifyVaultStrategyRules(vault, params.baseAsset, created.flexStrategy, vaultAddress);
        }

        _verifyVaultRoles(vault, verification);
    }

    function _verifyProvider(Verification calldata verification, address effectiveBaseAsset) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata params = verification.vaultParams;

        _verify(created.provider != address(0) && created.provider.code.length != 0, "provider code");

        if (verification.flexParams.deployStrategy) {
            FlexProvider provider = FlexProvider(created.provider);
            _verify(provider.baseAsset() == effectiveBaseAsset, "flex provider base");
            _verify(provider.defaultAsset() == params.baseAsset, "flex provider default");
            _verify(provider.strategy() == created.flexStrategy, "flex provider strategy");
            _verify(provider.getRate(effectiveBaseAsset) == PROVIDER_RATE, "flex provider base rate");
            _verify(provider.getRate(params.baseAsset) == PROVIDER_RATE, "flex provider default rate");
        } else {
            BaseAssetProvider provider = BaseAssetProvider(created.provider);
            _verify(provider.baseAsset() == effectiveBaseAsset, "provider base");
            _verify(provider.defaultAsset() == params.baseAsset, "provider default");
            _verify(provider.rate() == PROVIDER_RATE, "provider rate");
            _verify(provider.getRate(effectiveBaseAsset) == PROVIDER_RATE, "provider base rate");
            _verify(provider.getRate(params.baseAsset) == PROVIDER_RATE, "provider default rate");
        }
    }

    function _verifyWithdrawalSystem(Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata params = verification.vaultParams;
        IRegistry registry = IVaultFactoryView(verification.factory).REGISTRY();

        IWithdrawalRequestView request = IWithdrawalRequestView(created.withdrawalRequest);
        _verify(created.withdrawalRequest.code.length != 0, "request code");
        _verify(address(request.token()) == created.vault, "request token");
        _verify(address(request.bagFactory()) == created.bagFactory, "request bag factory");
        _verify(address(request.withdrawer()) == created.withdrawer, "request withdrawer");
        _verify(address(request.requestPolicy()) == created.requestPolicy, "request policy");
        _verify(request.maxDataLength() == params.maxDataLength, "request data length");
        _verify(request.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "request admin");
        _verify(request.hasRole(RESOLVER_ROLE, params.resolver), "request resolver");
        _verify(request.hasRole(CONFIGURATION_MANAGER_ROLE, created.timelock), "request config");
        _verify(request.hasRole(PAUSER_ROLE, params.pauser), "request pauser");
        _verify(!request.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "request dangling admin");
        _verify(!request.hasRole(CONFIGURATION_MANAGER_ROLE, verification.factory), "request dangling config");

        IWithdrawerView withdrawer = IWithdrawerView(created.withdrawer);
        _verify(created.withdrawer.code.length != 0, "withdrawer code");
        _verify(address(withdrawer.token()) == created.vault, "withdrawer token");
        _verify(withdrawer.withdrawalRequest() == created.withdrawalRequest, "withdrawer request");

        IBeaconProxyFactoryView bagFactory = IBeaconProxyFactoryView(created.bagFactory);
        _verify(created.bagFactory.code.length != 0, "bag factory code");
        _verify(bagFactory.implementation() == registry.valueOf(RegistryKeys.BAG), "bag implementation");
        _verify(bagFactory.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "bag admin");
        _verify(bagFactory.hasRole(CREATOR_ROLE, created.withdrawalRequest), "bag creator");
        _verify(bagFactory.hasRole(IMPLEMENTATION_MANAGER_ROLE, created.timelock), "bag implementation manager");
        _verify(!bagFactory.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "bag dangling admin");

        _verify(
            IRequestPolicyView(created.requestPolicy).minWithdrawalAmount() == params.minWithdrawalAmount,
            "request min amount"
        );
        _verify(IVaultView(created.vault).hasRole(ASSET_WITHDRAWER_ROLE, created.withdrawer), "vault withdrawer role");
    }

    function _verifyFlexStrategy(Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams calldata flexParams = verification.flexParams;

        IFlexStrategyView strategy = IFlexStrategyView(created.flexStrategy);
        _verify(created.flexStrategy.code.length != 0, "strategy code");
        _verifyString(strategy.name(), flexParams.strategyName, "strategy name");
        _verifyString(strategy.symbol(), flexParams.strategySymbol, "strategy symbol");
        _verify(strategy.decimals() == IERC20Metadata(vaultParams.baseAsset).decimals(), "strategy decimals");
        _verify(strategy.asset() == vaultParams.baseAsset, "strategy asset");
        _verify(address(strategy.accountingModule()) == created.accountingModule, "strategy module");
        _verify(strategy.hooks() == created.accountingModuleHook, "strategy hooks");
        _verify(strategy.alwaysComputeTotalAssets() == flexParams.alwaysComputeTotalAssets, "strategy accounting mode");
        _verify(!strategy.paused(), "strategy paused");
        _verify(strategy.getHasAllocator(), "strategy allocator flag");

        _verifyStrategyRoles(strategy, verification);
        _verifyStrategyRules(strategy, created.accountingModule, created.flexStrategy);
        _verifyAccountingSystem(verification);
    }

    function _verifyAccountingSystem(Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams calldata flexParams = verification.flexParams;

        IAccountingTokenView accountingToken = IAccountingTokenView(created.accountingToken);
        _verify(created.accountingToken.code.length != 0, "accounting token code");
        _verify(accountingToken.TRACKED_ASSET() == vaultParams.baseAsset, "accounting token asset");
        _verify(
            accountingToken.decimals() == IERC20Metadata(vaultParams.baseAsset).decimals(), "accounting token decimals"
        );
        _verify(accountingToken.accountingModule() == created.accountingModule, "accounting token module");
        _verify(accountingToken.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "accounting token admin");
        _verify(accountingToken.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock), "accounting token manager");
        _verify(!accountingToken.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "accounting token dangling admin");
        _verify(
            !accountingToken.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, verification.factory),
            "accounting token dangling manager"
        );

        IAccountingModuleView accountingModule = IAccountingModuleView(created.accountingModule);
        _verify(created.accountingModule.code.length != 0, "accounting module code");
        _verify(accountingModule.strategy() == created.flexStrategy, "accounting module strategy");
        _verify(accountingModule.baseAsset() == vaultParams.baseAsset, "accounting module asset");
        _verify(address(accountingModule.accountingToken()) == created.accountingToken, "accounting module token");
        _verify(accountingModule.safe() == flexParams.multisig, "accounting module safe");
        _verify(accountingModule.targetApy() == flexParams.targetApy, "accounting target apy");
        _verify(accountingModule.lowerBound() == flexParams.lowerBound, "accounting lower bound");
        _verify(accountingModule.cooldownSeconds() == ACCOUNTING_COOLDOWN_SECONDS, "accounting cooldown");
        _verify(accountingModule.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "accounting module admin");
        _verify(accountingModule.hasRole(SAFE_MANAGER_ROLE, created.timelock), "accounting module safe manager");
        _verify(
            accountingModule.hasRole(REWARDS_PROCESSOR_ROLE, flexParams.accountingProcessor),
            "accounting rewards processor"
        );
        _verify(accountingModule.hasRole(LOSS_PROCESSOR_ROLE, flexParams.multisig), "accounting loss processor");
        _verify(!accountingModule.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "accounting module dangling admin");

        if (created.rewardsSweeper != address(0)) {
            IRewardsSweeperView sweeper = IRewardsSweeperView(created.rewardsSweeper);
            _verify(sweeper.accountingModule() == created.accountingModule, "sweeper module");
            _verify(sweeper.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "sweeper admin");
            _verify(sweeper.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock), "sweeper manager");
            _verify(sweeper.hasRole(REWARDS_SWEEPER_ROLE, vaultParams.processor), "sweeper role");
            _verify(sweeper.hasRole(SNAPSHOT_REWARDS_SWEEPER_ROLE, vaultParams.processor), "sweeper snapshot role");
            _verify(
                accountingModule.hasRole(REWARDS_PROCESSOR_ROLE, created.rewardsSweeper), "sweeper rewards processor"
            );
            _verify(!sweeper.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "sweeper dangling admin");
            _verify(!sweeper.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, verification.factory), "sweeper dangling manager");
        } else {
            _verify(!flexParams.deployRewardsSweeper, "missing sweeper");
        }
    }

    function _verifySafeGuard(Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata vaultParams = verification.vaultParams;
        IVaultFactory.FlexStrategyParams calldata flexParams = verification.flexParams;

        ISafeGuardView safeGuard = ISafeGuardView(created.safeGuard);
        _verify(created.safeGuard.code.length != 0, "safeguard code");
        _verifyString(safeGuard.name(), string.concat(flexParams.strategyName, " Safeguard"), "safeguard name");
        _verify(safeGuard.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "safeguard admin");
        _verify(safeGuard.hasRole(PROCESSOR_MANAGER_ROLE, created.timelock), "safeguard processor manager");
        _verify(safeGuard.hasRole(GUARD_ADMIN_ROLE, created.timelock), "safeguard guard admin");
        _verify(!safeGuard.hasRole(DEFAULT_ADMIN_ROLE, verification.factory), "safeguard dangling admin");
        _verify(
            !safeGuard.hasRole(PROCESSOR_MANAGER_ROLE, verification.factory), "safeguard dangling processor manager"
        );
        _verify(!safeGuard.hasRole(GUARD_ADMIN_ROLE, verification.factory), "safeguard dangling guard admin");

        ISafeGuard.FunctionRule memory rule =
            safeGuard.getProcessorRule(vaultParams.baseAsset, IERC20.transfer.selector);
        _verify(rule.isActive, "safeguard transfer inactive");
        _verify(rule.validator == address(0), "safeguard transfer validator");
        _verify(rule.paramRules.length == 2, "safeguard transfer params");
        _verifyAddressParam(rule.paramRules[0], flexParams.offRampAddress, "safeguard transfer recipient");
        _verifyUintParam(rule.paramRules[1], "safeguard transfer amount");
    }

    function _verifyHooks(Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IAccountingModuleHookView hook = IAccountingModuleHookView(created.accountingModuleHook);

        _verify(created.accountingModuleHook.code.length != 0, "hook code");
        _verify(address(hook.VAULT()) == created.flexStrategy, "hook vault");
        _verify(address(hook.flexStrategy()) == created.flexStrategy, "hook strategy");
        _verify(address(hook.accountingModule()) == created.accountingModule, "hook module");
    }

    function _verifyNoFlexComponents(IVaultFactory.CreatedVault calldata created) internal pure {
        _verify(created.safeGuard == address(0), "unexpected safeguard");
        _verify(created.accountingModuleHook == address(0), "unexpected hook");
        _verify(created.flexStrategy == address(0), "unexpected strategy");
        _verify(created.accountingToken == address(0), "unexpected accounting token");
        _verify(created.accountingModule == address(0), "unexpected accounting module");
        _verify(created.rewardsSweeper == address(0), "unexpected sweeper");
    }

    function _verifyVaultRoles(IVaultView vault, Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata params = verification.vaultParams;
        address factory = verification.factory;

        _verify(vault.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "vault admin role");
        _verify(vault.hasRole(PROCESSOR_ROLE, params.processor), "vault processor role");
        _verify(vault.hasRole(PAUSER_ROLE, params.pauser), "vault pauser role");
        _verify(vault.hasRole(UNPAUSER_ROLE, params.unpauser), "vault unpauser role");
        _verify(vault.hasRole(FEE_MANAGER_ROLE, params.feeManager), "vault fee role");
        _verify(vault.hasRole(PROVIDER_MANAGER_ROLE, created.timelock), "vault provider role");
        _verify(vault.hasRole(BUFFER_MANAGER_ROLE, created.timelock), "vault buffer role");
        _verify(vault.hasRole(ASSET_MANAGER_ROLE, created.timelock), "vault asset role");
        _verify(vault.hasRole(PROCESSOR_MANAGER_ROLE, created.timelock), "vault processor manager role");
        _verify(vault.hasRole(HOOKS_MANAGER_ROLE, created.timelock), "vault hooks role");

        _verify(!vault.hasRole(DEFAULT_ADMIN_ROLE, factory), "vault dangling admin");
        _verify(!vault.hasRole(PROVIDER_MANAGER_ROLE, factory), "vault dangling provider");
        _verify(!vault.hasRole(BUFFER_MANAGER_ROLE, factory), "vault dangling buffer");
        _verify(!vault.hasRole(ASSET_MANAGER_ROLE, factory), "vault dangling asset");
        _verify(!vault.hasRole(PROCESSOR_MANAGER_ROLE, factory), "vault dangling processor manager");
        _verify(!vault.hasRole(HOOKS_MANAGER_ROLE, factory), "vault dangling hooks");
        _verify(!vault.hasRole(UNPAUSER_ROLE, factory), "vault dangling unpauser");
    }

    function _verifyStrategyRoles(IFlexStrategyView strategy, Verification calldata verification) internal view {
        IVaultFactory.CreatedVault calldata created = verification.created;
        IVaultFactory.VaultParams calldata params = verification.vaultParams;
        address factory = verification.factory;

        _verify(strategy.hasRole(DEFAULT_ADMIN_ROLE, created.timelock), "strategy admin role");
        _verify(strategy.hasRole(PROCESSOR_ROLE, params.processor), "strategy processor role");
        _verify(strategy.hasRole(PAUSER_ROLE, params.pauser), "strategy pauser role");
        _verify(strategy.hasRole(UNPAUSER_ROLE, params.unpauser), "strategy unpauser role");
        _verify(strategy.hasRole(PROVIDER_MANAGER_ROLE, created.timelock), "strategy provider role");
        _verify(strategy.hasRole(ASSET_MANAGER_ROLE, created.timelock), "strategy asset role");
        _verify(strategy.hasRole(BUFFER_MANAGER_ROLE, created.timelock), "strategy buffer role");
        _verify(strategy.hasRole(PROCESSOR_MANAGER_ROLE, created.timelock), "strategy processor manager role");
        _verify(strategy.hasRole(ALLOCATOR_MANAGER_ROLE, created.timelock), "strategy allocator manager role");
        _verify(strategy.hasRole(HOOKS_MANAGER_ROLE, created.timelock), "strategy hooks role");
        _verify(strategy.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, created.timelock), "strategy module manager role");
        _verify(strategy.hasRole(ALLOCATOR_ROLE, created.vault), "strategy allocator role");
        _verify(strategy.hasRole(PROCESSOR_ROLE, created.accountingModuleHook), "strategy hook processor role");

        _verify(!strategy.hasRole(DEFAULT_ADMIN_ROLE, factory), "strategy dangling admin");
        _verify(!strategy.hasRole(PROCESSOR_MANAGER_ROLE, factory), "strategy dangling processor manager");
        _verify(!strategy.hasRole(ALLOCATOR_MANAGER_ROLE, factory), "strategy dangling allocator manager");
        _verify(!strategy.hasRole(ALLOCATOR_ROLE, factory), "strategy dangling allocator");
        _verify(!strategy.hasRole(HOOKS_MANAGER_ROLE, factory), "strategy dangling hooks");
        _verify(!strategy.hasRole(UNPAUSER_ROLE, factory), "strategy dangling unpauser");
        _verify(!strategy.hasRole(ACCOUNTING_MODULE_MANAGER_ROLE, factory), "strategy dangling module manager");
    }

    function _verifyVaultStrategyRules(IVaultView vault, address baseAsset, address strategy, address expectedVault)
        internal
        view
    {
        _verifyRule2(
            vault.getProcessorRule(baseAsset, IERC20.approve.selector), strategy, address(0), "vault approve rule"
        );
        _verifyRule2(
            vault.getProcessorRule(strategy, bytes4(keccak256("deposit(uint256,address)"))),
            address(0),
            expectedVault,
            "vault strategy deposit rule"
        );
        _verifyRule2(
            vault.getProcessorRule(strategy, bytes4(keccak256("mint(uint256,address)"))),
            address(0),
            expectedVault,
            "vault strategy mint rule"
        );
        _verifyRule3(
            vault.getProcessorRule(strategy, bytes4(keccak256("withdraw(uint256,address,address)"))),
            expectedVault,
            expectedVault,
            "vault strategy withdraw rule"
        );
        _verifyRule3(
            vault.getProcessorRule(strategy, bytes4(keccak256("redeem(uint256,address,address)"))),
            expectedVault,
            expectedVault,
            "vault strategy redeem rule"
        );
    }

    function _verifyStrategyRules(IFlexStrategyView strategy, address accountingModule, address expectedStrategy)
        internal
        view
    {
        _verifyRule1(
            strategy.getProcessorRule(accountingModule, bytes4(keccak256("deposit(uint256)"))),
            "strategy module deposit rule"
        );
        _verifyRule2(
            strategy.getProcessorRule(accountingModule, bytes4(keccak256("withdraw(uint256,address)"))),
            address(0),
            expectedStrategy,
            "strategy module withdraw rule"
        );
    }

    function _verifyRule1(IVault.FunctionRule memory rule, string memory check) internal pure {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 1, check);
        _verifyUintParam(rule.paramRules[0], check);
    }

    function _verifyRule2(IVault.FunctionRule memory rule, address p0Allowed, address p1Allowed, string memory check)
        internal
        pure
    {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 2, check);
        if (p0Allowed == address(0)) _verifyUintParam(rule.paramRules[0], check);
        else _verifyAddressParam(rule.paramRules[0], p0Allowed, check);
        if (p1Allowed == address(0)) _verifyUintParam(rule.paramRules[1], check);
        else _verifyAddressParam(rule.paramRules[1], p1Allowed, check);
    }

    function _verifyRule3(IVault.FunctionRule memory rule, address p1Allowed, address p2Allowed, string memory check)
        internal
        pure
    {
        _verify(rule.isActive, check);
        _verify(rule.validator == address(0), check);
        _verify(rule.paramRules.length == 3, check);
        _verifyUintParam(rule.paramRules[0], check);
        _verifyAddressParam(rule.paramRules[1], p1Allowed, check);
        _verifyAddressParam(rule.paramRules[2], p2Allowed, check);
    }

    function _verifyAddressParam(IVault.ParamRule memory param, address allowed, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(IVault.ParamType.ADDRESS), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 1, check);
        _verify(param.allowList[0] == allowed, check);
    }

    function _verifyAddressParam(ISafeGuard.ParamRule memory param, address allowed, string memory check)
        internal
        pure
    {
        _verify(uint256(param.paramType) == uint256(ISafeGuard.ParamType.ADDRESS), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 1, check);
        _verify(param.allowList[0] == allowed, check);
    }

    function _verifyUintParam(IVault.ParamRule memory param, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(IVault.ParamType.UINT256), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 0, check);
    }

    function _verifyUintParam(ISafeGuard.ParamRule memory param, string memory check) internal pure {
        _verify(uint256(param.paramType) == uint256(ISafeGuard.ParamType.UINT256), check);
        _verify(!param.isArray, check);
        _verify(param.allowList.length == 0, check);
    }

    function _verifyWrappedToken(address wrappedToken, address underlying, uint8 underlyingDecimals) internal view {
        IWrappedTokenView wrapper = IWrappedTokenView(wrappedToken);
        _verify(wrappedToken != address(0) && wrappedToken.code.length != 0, "wrapper code");
        _verify(wrapper.asset() == underlying, "wrapper asset");
        _verify(wrapper.decimals() == VAULT_DECIMALS, "wrapper decimals");
        _verify(wrapper.decimalsOffset() == VAULT_DECIMALS - underlyingDecimals, "wrapper offset");
    }

    function _effectiveBaseAsset(
        IVaultFactory.CreatedVault calldata created,
        IVaultFactory.VaultParams calldata params,
        uint8 baseAssetDecimals
    ) internal pure returns (address) {
        return baseAssetDecimals == VAULT_DECIMALS ? params.baseAsset : created.wrappedToken;
    }

    function _defaultAssetIndex(uint8 baseAssetDecimals) internal pure returns (uint256) {
        return baseAssetDecimals == VAULT_DECIMALS ? 0 : 1;
    }

    function _verifyString(string memory actual, string memory expected, string memory check) internal pure {
        _verify(keccak256(bytes(actual)) == keccak256(bytes(expected)), check);
    }

    function _verify(bool condition, string memory check) internal pure {
        if (!condition) revert VerificationFailed(check);
    }
}

interface IVaultFactoryView {
    function REGISTRY() external view returns (IRegistry);
}

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IVaultView is IAccessControlView {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function asset() external view returns (address);
    function countNativeAsset() external view returns (bool);
    function alwaysComputeTotalAssets() external view returns (bool);
    function baseWithdrawalFee() external view returns (uint64);
    function defaultAssetIndex() external view returns (uint256);
    function provider() external view returns (address);
    function buffer() external view returns (address);
    function paused() external view returns (bool);
    function getAssets() external view returns (address[] memory);
    function getProcessorRule(address contractAddress, bytes4 funcSig)
        external
        view
        returns (IVault.FunctionRule memory);
}

interface IFlexStrategyView is IAccessControlView {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function asset() external view returns (address);
    function accountingModule() external view returns (address);
    function hooks() external view returns (address);
    function alwaysComputeTotalAssets() external view returns (bool);
    function paused() external view returns (bool);
    function getHasAllocator() external view returns (bool);
    function getProcessorRule(address contractAddress, bytes4 funcSig)
        external
        view
        returns (IVault.FunctionRule memory);
}

interface IAccountingTokenView is IAccessControlView {
    function TRACKED_ASSET() external view returns (address);
    function decimals() external view returns (uint8);
    function accountingModule() external view returns (address);
}

interface IAccountingModuleView is IAccessControlView {
    function baseAsset() external view returns (address);
    function strategy() external view returns (address);
    function accountingToken() external view returns (address);
    function safe() external view returns (address);
    function targetApy() external view returns (uint256);
    function lowerBound() external view returns (uint256);
    function cooldownSeconds() external view returns (uint16);
}

interface IRewardsSweeperView is IAccessControlView {
    function accountingModule() external view returns (address);
}

interface ISafeGuardView is IAccessControlView {
    function name() external view returns (string memory);
    function getProcessorRule(address contractAddress, bytes4 funcSig)
        external
        view
        returns (ISafeGuard.FunctionRule memory);
}

interface IAccountingModuleHookView {
    function VAULT() external view returns (address);
    function flexStrategy() external view returns (address);
    function accountingModule() external view returns (address);
}

interface IWrappedTokenView {
    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function decimalsOffset() external view returns (uint8);
}

interface IWithdrawalRequestView is IAccessControlView {
    function token() external view returns (address);
    function bagFactory() external view returns (address);
    function withdrawer() external view returns (address);
    function requestPolicy() external view returns (address);
    function maxDataLength() external view returns (uint256);
}

interface IWithdrawerView {
    function token() external view returns (address);
    function withdrawalRequest() external view returns (address);
}

interface IBeaconProxyFactoryView is IAccessControlView {
    function implementation() external view returns (address);
}

interface IRequestPolicyView {
    function minWithdrawalAmount() external view returns (uint256);
}
