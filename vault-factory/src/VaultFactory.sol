// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {IWrappedToken} from "src/interfaces/external/IWrappedToken.sol";
import {FlexStrategyDeployer} from "src/lib/FlexStrategyDeployer.sol";
import {IFlexStrategy} from "src/interfaces/external/IFlexStrategy.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {SafeGuardDeployer} from "src/lib/SafeGuardDeployer.sol";
import {TimelockDeployer} from "src/lib/TimelockDeployer.sol";
import {WithdrawalSystemDeployer} from "src/lib/WithdrawalSystemDeployer.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";

contract NonceMarker {}

contract VaultFactory is IVaultFactory {
    using SafeERC20 for IERC20;

    /// STORAGE ///

    string public constant VERSION = "0.1.0";
    uint8 public constant VAULT_DECIMALS = 18;
    uint64 public constant BASE_WITHDRAWAL_FEE = 0;
    /// @notice 18-decimal base units per whole default-asset token, i.e. par.
    uint256 public constant PROVIDER_RATE = 1e18;

    struct Assets {
        address effectiveBaseAsset;
        address defaultAsset;
        uint256 defaultAssetIndex;
        address wrappedToken;
    }

    struct PendingDeployment {
        address creator;
        VaultParams vaultParams;
        FlexStrategyParams flexParams;
        CreatedVault created;
        Assets assets;
    }

    IRegistry public immutable REGISTRY;
    mapping(bytes32 deploymentId => PendingDeployment) private pendingDeployments;

    /// CONSTRUCTOR ///

    constructor(IRegistry registry) {
        if (address(registry) == address(0)) revert ZeroAddress();
        REGISTRY = registry;
    }

    /// VAULT CREATION ///

    function createVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (CreatedVault memory created)
    {
        (bytes32 deploymentId,) = _startCreateVault(msg.sender, params, flexParams);
        created = _resumeCreateVault(deploymentId, msg.sender);
    }

    function startCreateVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (bytes32 deploymentId, CreatedVault memory created)
    {
        return _startCreateVault(msg.sender, params, flexParams);
    }

    function resumeCreateVault(bytes32 deploymentId) external returns (CreatedVault memory created) {
        return _resumeCreateVault(deploymentId, msg.sender);
    }

    function _startCreateVault(address creator, VaultParams calldata params, FlexStrategyParams calldata flexParams)
        internal
        returns (bytes32 deploymentId, CreatedVault memory created)
    {
        _validateVaultParams(params);
        if (flexParams.deployStrategy) {
            _validateFlexParams(flexParams);
        }

        TimelockController timelock = TimelockDeployer.deploy(params.admin, params.timelockDuration);
        address vaultLogic = _registryValue(RegistryKeys.VAULT);
        Assets memory assets = _prepareAssets(params, address(timelock));

        created.timelock = address(timelock);
        created.wrappedToken = assets.wrappedToken;
        created.vault = address(new UninitializedTransparentUpgradeableProxy(vaultLogic, address(timelock)));
        if (!flexParams.deployStrategy) {
            created.provider =
                address(new BaseAssetProvider(assets.effectiveBaseAsset, assets.defaultAsset, PROVIDER_RATE));
        } else {
            created.safeGuard = SafeGuardDeployer.deploy(
                SafeGuardDeployer.Config({
                    safeGuardLogic: _registryValue(RegistryKeys.SAFE_GUARD),
                    timelock: address(timelock),
                    baseAsset: params.baseAsset,
                    offRampAddress: flexParams.offRampAddress,
                    strategyName: flexParams.strategyName
                })
            );
        }

        IVault vault = IVault(created.vault);
        _initializeVault(vault, params, assets);
        _configureVault(vault, assets, params, created.provider, address(timelock));

        deploymentId = keccak256(abi.encode(block.chainid, address(this), creator, created.vault));
        PendingDeployment storage pending = pendingDeployments[deploymentId];
        pending.creator = creator;
        pending.vaultParams = params;
        pending.flexParams = flexParams;
        pending.created = created;
        pending.assets = assets;

        emit VaultCreationStarted(creator, deploymentId, created.vault, created);
    }

    function _resumeCreateVault(bytes32 deploymentId, address caller) internal returns (CreatedVault memory created) {
        PendingDeployment storage pending = pendingDeployments[deploymentId];
        if (pending.creator == address(0)) revert UnknownDeployment(deploymentId);
        if (pending.creator != caller) revert Unauthorized();

        VaultParams memory params = pending.vaultParams;
        FlexStrategyParams memory flexParams = pending.flexParams;
        Assets memory assets = pending.assets;
        created = pending.created;

        IVault vault = IVault(created.vault);
        if (flexParams.deployStrategy) {
            FlexStrategyDeployer.FlexSystem memory flex =
                FlexStrategyDeployer.deploy(_flexConfig(created.vault, created.timelock, params, flexParams, assets));
            created.flexStrategy = flex.strategy;
            created.accountingToken = flex.accountingToken;
            created.accountingModule = flex.accountingModule;
            created.accountingModuleHook = flex.accountingModuleHook;
            created.rewardsSweeper = flex.rewardsSweeper;
            created.provider = flex.vaultProvider;
            vault.setProvider(created.provider);
            // The strategy's shares are an accounting-only vault asset, priced by the
            // FlexProvider at the strategy's live redemption rate. active MUST be false: it
            // gates vault-side deposits of the asset, and strategy shares must never be
            // depositable into the vault. The vault's processor operates the strategy through
            // the preloaded rules only.
            vault.addAsset(created.flexStrategy, false);
            FlexStrategyDeployer.configureVaultRules(created.vault, created.flexStrategy, params.baseAsset);
        }

        WithdrawalSystem memory withdrawals = deployWithdrawalSystem(
            created.vault,
            created.timelock,
            params.resolver,
            params.pauser,
            params.minWithdrawalAmount,
            params.maxDataLength
        );
        created.withdrawalRequest = withdrawals.withdrawalRequest;
        created.withdrawer = withdrawals.withdrawer;
        created.bagFactory = withdrawals.bagFactory;
        created.requestPolicy = withdrawals.requestPolicy;
        vault.grantRole(vault.ASSET_WITHDRAWER_ROLE(), withdrawals.withdrawer);

        _bootstrap(vault, params);
        if (flexParams.deployStrategy) {
            _bootstrapStrategy(created.flexStrategy, created.vault, params);
        }

        // Refresh cached accounting after direct bootstrap mints. The main vault prices strategy
        // shares through the strategy, so refresh the strategy first when it uses cached totals.
        if (flexParams.deployStrategy && !flexParams.alwaysComputeTotalAssets) {
            IFlexStrategy(created.flexStrategy).processAccounting();
        }
        if (!params.alwaysComputeTotalAssets) {
            vault.processAccounting();
        }

        _renounceTemporaryRoles(vault);

        delete pendingDeployments[deploymentId];

        emit VaultCreated(caller, created.vault, created.timelock, created);
    }

    function _validateVaultParams(VaultParams calldata params) internal view {
        if (
            params.admin == address(0) || params.processor == address(0) || params.pauser == address(0)
                || params.unpauser == address(0) || params.feeManager == address(0) || params.resolver == address(0)
                || params.baseAsset == address(0) || params.bootstrapReceiver == address(0)
        ) {
            revert ZeroAddress();
        }

        uint8 baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        if (baseAssetDecimals > VAULT_DECIMALS) revert AssetDecimalsTooHigh(baseAssetDecimals);
        uint256 minBootstrapAmount = 10 ** baseAssetDecimals;
        if (params.bootstrapAmount < minBootstrapAmount) {
            revert BootstrapAmountTooLow(params.bootstrapAmount, minBootstrapAmount);
        }
    }

    function _validateFlexParams(FlexStrategyParams calldata flexParams) internal pure {
        if (
            flexParams.multisig == address(0) || flexParams.accountingProcessor == address(0)
                || flexParams.offRampAddress == address(0)
        ) {
            revert ZeroAddress();
        }
    }

    function _prepareAssets(VaultParams memory params, address timelock) internal returns (Assets memory assets) {
        uint8 baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        assets.defaultAsset = params.baseAsset;

        if (baseAssetDecimals == VAULT_DECIMALS) {
            assets.effectiveBaseAsset = params.baseAsset;
        } else {
            assets.wrappedToken = _deployWrappedToken(params.baseAsset, baseAssetDecimals, timelock);
            assets.effectiveBaseAsset = assets.wrappedToken;
        }

        assets.defaultAssetIndex = assets.effectiveBaseAsset == assets.defaultAsset ? 0 : 1;
    }

    function _deployWrappedToken(address underlying, uint8 underlyingDecimals, address timelock)
        internal
        returns (address wrappedToken)
    {
        wrappedToken = address(
            new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WRAPPED_TOKEN), timelock)
        );
        IWrappedToken(wrappedToken)
            .initialize(
                IERC20(underlying),
                _wrappedTokenName(underlying),
                _wrappedTokenSymbol(underlying),
                VAULT_DECIMALS,
                VAULT_DECIMALS - underlyingDecimals
            );
    }

    function _initializeVault(IVault vault, VaultParams memory params, Assets memory assets) internal {
        vault.initialize(
            address(this),
            params.tokenName,
            params.tokenSymbol,
            VAULT_DECIMALS,
            BASE_WITHDRAWAL_FEE,
            params.countNativeAsset,
            params.alwaysComputeTotalAssets,
            assets.defaultAssetIndex
        );
    }

    function _configureVault(
        IVault vault,
        Assets memory assets,
        VaultParams memory params,
        address provider,
        address timelock
    ) internal {
        _grantTemporaryRoles(vault);

        // IMPORTANT: the vault's DEFAULT_ADMIN_ROLE must be held by the timelock and nothing
        // else. It is the role admin for every vault role, so this is what forces critical role
        // updates (e.g. granting or revoking PROVIDER_MANAGER_ROLE or ASSET_MANAGER_ROLE) through
        // a scheduled, delayed timelock operation. Granting it to any other account would let
        // that account rewire vault roles instantly, bypassing the timelock entirely.
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_ROLE(), params.processor);
        vault.grantRole(vault.PAUSER_ROLE(), params.pauser);
        vault.grantRole(vault.UNPAUSER_ROLE(), params.unpauser);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), params.feeManager);

        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), timelock);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), timelock);

        // The effective base asset is active only when it is itself the ERC4626 default asset
        // (the 18-decimal, no-wrapper case), which must accept deposits. A wrapper is an
        // accounting-only denominator and MUST NOT be depositable into the vault; only the
        // default asset takes deposits.
        bool effectiveBaseAssetIsDefaultAsset = assets.defaultAssetIndex == 0;
        vault.addAsset(assets.effectiveBaseAsset, effectiveBaseAssetIsDefaultAsset);
        if (assets.defaultAssetIndex == 1) {
            vault.addAsset(assets.defaultAsset, true);
        }
        if (provider != address(0)) {
            vault.setProvider(provider);
        }
        vault.setBuffer(address(0));
    }

    function _bootstrap(IVault vault, VaultParams memory params) internal {
        IERC20 asset = IERC20(params.baseAsset);
        uint8 baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        uint256 expectedShares = params.bootstrapAmount * 10 ** (VAULT_DECIMALS - baseAssetDecimals);

        asset.safeTransferFrom(msg.sender, address(this), params.bootstrapAmount);
        asset.forceApprove(address(vault), params.bootstrapAmount);
        vault.unpause();
        uint256 shares = vault.deposit(params.bootstrapAmount, params.bootstrapReceiver);

        // The vault address is CREATE-predictable before deployment, so it can be prefunded.
        // With live accounting enabled, prefunded balances are included while totalSupply is still
        // zero, which can dilute the bootstrap deposit down to fewer shares or even zero. The
        // first mint must therefore match the exact 1:1 normalized amount expected for an empty
        // vault configured with the factory's fixed par provider.
        if (shares != expectedShares) revert BootstrapSharesMismatch(shares, expectedShares);
        asset.forceApprove(address(vault), 0);
    }

    /// @dev The factory's setup roles on the vault. DEFAULT_ADMIN_ROLE is not granted here - the
    /// factory receives it in the vault initializer - but it is renounced below with the rest.
    function _grantTemporaryRoles(IVault vault) internal {
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _renounceTemporaryRoles(IVault vault) internal {
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.UNPAUSER_ROLE(), address(this));
    }

    /// FLEX STRATEGY ///

    function _flexConfig(
        address vault,
        address timelock,
        VaultParams memory params,
        FlexStrategyParams memory flexParams,
        Assets memory assets
    ) internal view returns (FlexStrategyDeployer.Config memory cfg) {
        cfg.vault = vault;
        cfg.effectiveBaseAsset = assets.effectiveBaseAsset;
        cfg.timelock = timelock;
        cfg.baseAsset = params.baseAsset;
        cfg.baseAssetDecimals = IERC20Metadata(params.baseAsset).decimals();
        cfg.alwaysComputeTotalAssets = flexParams.alwaysComputeTotalAssets;
        cfg.deployRewardsSweeper = flexParams.deployRewardsSweeper;
        cfg.processor = params.processor;
        cfg.pauser = params.pauser;
        cfg.unpauser = params.unpauser;
        cfg.strategyLogic = _registryValue(RegistryKeys.FLEX_STRATEGY);
        cfg.accountingModuleLogic = _registryValue(RegistryKeys.ACCOUNTING_MODULE);
        cfg.accountingTokenFactory = _registryValue(RegistryKeys.ACCOUNTING_TOKEN_FACTORY);
        cfg.hooksDeployer = _registryValue(RegistryKeys.HOOKS_DEPLOYER);
        if (flexParams.deployRewardsSweeper) {
            cfg.rewardsSweeperLogic = _registryValue(RegistryKeys.REWARDS_SWEEPER);
        }
        cfg.safe = flexParams.multisig;
        cfg.accountingProcessor = flexParams.accountingProcessor;
        cfg.targetApy = flexParams.targetApy;
        cfg.lowerBound = flexParams.lowerBound;
        cfg.minRewardableAssets = flexParams.minRewardableAssets;
        cfg.strategyName = flexParams.strategyName;
        cfg.strategySymbol = flexParams.strategySymbol;
        cfg.accountingTokenName = flexParams.accountingTokenName;
        cfg.accountingTokenSymbol = flexParams.accountingTokenSymbol;
    }

    /// @dev Deposits one bootstrap amount of the base asset into the strategy with the vault as
    /// the receiver of the strategy shares, then renounces the factory's ALLOCATOR_ROLE. Runs
    /// after the vault bootstrap so the strategy shares cannot dilute the vault's first mint.
    function _bootstrapStrategy(address strategy, address vault, VaultParams memory params) internal {
        IERC20 asset = IERC20(params.baseAsset);

        asset.safeTransferFrom(msg.sender, address(this), params.bootstrapAmount);
        asset.forceApprove(strategy, params.bootstrapAmount);
        uint256 shares = IFlexStrategy(strategy).deposit(params.bootstrapAmount, vault);

        // Same prefund protection as the vault bootstrap: the strategy is empty and its fixed
        // rate provider prices the base asset at par, so the first mint must be exactly 1:1 in
        // the strategy's own decimals.
        if (shares != params.bootstrapAmount) revert BootstrapSharesMismatch(shares, params.bootstrapAmount);
        asset.forceApprove(strategy, 0);

        IFlexStrategy(strategy).renounceRole(FlexStrategyDeployer.ALLOCATOR_ROLE, address(this));
    }

    /// WITHDRAWAL SYSTEM ///

    /// @notice Deploys the async withdrawal system for a vault. Callable standalone for vaults
    /// not created through this factory; the caller is then responsible for granting the returned
    /// withdrawer the vault's ASSET_WITHDRAWER_ROLE (createVault does this itself).
    function deployWithdrawalSystem(
        address vault,
        address timelock,
        address resolver,
        address pauser,
        uint256 minWithdrawalAmount,
        uint256 maxDataLength
    ) public returns (WithdrawalSystem memory withdrawals) {
        if (vault == address(0) || timelock == address(0) || resolver == address(0) || pauser == address(0)) {
            revert ZeroAddress();
        }

        withdrawals = WithdrawalSystemDeployer.deploy(
            WithdrawalSystemDeployer.Config({
                vault: vault,
                timelock: timelock,
                resolver: resolver,
                pauser: pauser,
                minWithdrawalAmount: minWithdrawalAmount,
                maxDataLength: maxDataLength,
                withdrawalRequestLogic: _registryValue(RegistryKeys.WITHDRAWAL_REQUEST),
                withdrawerLogic: _registryValue(RegistryKeys.WITHDRAWER),
                bagFactoryLogic: _registryValue(RegistryKeys.BAG_FACTORY),
                bagLogic: _registryValue(RegistryKeys.BAG)
            })
        );

        emit WithdrawalSystemDeployed(vault, timelock, withdrawals);
    }

    /// HELPERS ///

    function _registryValue(bytes32 key) internal view returns (address value) {
        value = REGISTRY.valueOf(key);
        if (value == address(0)) revert MissingRegistryValue(key);
    }

    function _wrappedTokenName(address underlying) internal view returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(underlying).name());
    }

    function _wrappedTokenSymbol(address underlying) internal view returns (string memory) {
        return string.concat("W", IERC20Metadata(underlying).symbol());
    }

    /// NONCE ///

    /// @notice Advances the factory CREATE nonce without deploying a vault.
    /// @dev Intended as an operational escape hatch if a future CREATE-derived vault address is
    /// prefunded before createVault executes.
    function advanceNonce() external returns (address marker) {
        marker = address(new NonceMarker());
        emit NonceAdvanced(msg.sender, marker);
    }
}
