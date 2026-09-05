// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20Metadata} from "src/interfaces/external/IERC20Metadata.sol";
import {IBeaconProxyFactory} from "src/interfaces/external/IBeaconProxyFactory.sol";
import {IVault} from "src/interfaces/external/IVault.sol";
import {IWithdrawalRequest} from "src/interfaces/external/IWithdrawalRequest.sol";
import {IWithdrawer} from "src/interfaces/external/IWithdrawer.sol";
import {IWrappedToken} from "src/interfaces/external/IWrappedToken.sol";
import {MinAmountRequestPolicy} from "yieldnest-vault-withdrawals/src/policies/MinAmountRequestPolicy.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {TimelockDeployer} from "src/lib/TimelockDeployer.sol";
import {UninitializedTransparentUpgradeableProxy} from "src/proxy/UninitializedTransparentUpgradeableProxy.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";

contract VaultFactory is IVaultFactory {
    using SafeERC20 for IERC20;

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

    IRegistry public immutable REGISTRY;

    constructor(IRegistry registry) {
        if (address(registry) == address(0)) revert ZeroAddress();
        REGISTRY = registry;
    }

    function createVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (CreatedVault memory created)
    {
        _validateVaultParams(params);

        TimelockController timelock = TimelockDeployer.deploy(params.admin, params.timelockDuration);
        address vaultLogic = _registryValue(RegistryKeys.VAULT);
        Assets memory assets = _prepareAssets(params, address(timelock));

        created.timelock = address(timelock);
        created.wrappedToken = assets.wrappedToken;
        created.vault = address(new UninitializedTransparentUpgradeableProxy(vaultLogic, address(timelock)));

        if (flexParams.deployStrategy) {
            // TODO: Deploy and configure the flex strategy once its deployment API is finalized.
            // TODO: Deploy the yieldnest-vault Provider wired to the wrapper and the flex strategy
            // instead of the single-asset BaseAssetProvider.
            // TODO: Deploy and configure the flex strategy SafeGuard once its deployment API is finalized.
            revert FunctionalityUnavailable();
        }
        // The wrapper never holds a balance, so only the default asset needs a rate.
        created.provider = address(new BaseAssetProvider(assets.defaultAsset, PROVIDER_RATE));

        IVault vault = IVault(created.vault);
        _initializeVault(vault, params, assets);
        _configureVault(vault, assets, params, created.provider, address(timelock));

        WithdrawalSystem memory withdrawals = deployWithdrawalSystem(
            created.vault,
            address(timelock),
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
        _renounceTemporaryRoles(vault);

        emit VaultCreated(msg.sender, created.vault, created.timelock, created);
    }

    function _initializeVault(IVault vault, VaultParams calldata params, Assets memory assets) internal {
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

    function _prepareAssets(VaultParams calldata params, address timelock) internal returns (Assets memory assets) {
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

    function _configureVault(
        IVault vault,
        Assets memory assets,
        VaultParams calldata params,
        address provider,
        address timelock
    ) internal {
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));

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

        vault.addAsset(assets.effectiveBaseAsset, true);
        if (assets.defaultAssetIndex == 1) {
            vault.addAsset(assets.defaultAsset, true);
        }
        vault.setProvider(provider);
        vault.setBuffer(address(0));
    }

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

        // The withdrawal request proxy is deployed uninitialized first because the withdrawer and
        // the bag factory both need its address during their own initialization.
        withdrawals.withdrawalRequest = address(
            new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WITHDRAWAL_REQUEST), timelock)
        );

        withdrawals.withdrawer =
            address(new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.WITHDRAWER), timelock));
        IWithdrawer(withdrawals.withdrawer).initialize(vault, withdrawals.withdrawalRequest);

        withdrawals.bagFactory =
            address(new UninitializedTransparentUpgradeableProxy(_registryValue(RegistryKeys.BAG_FACTORY), timelock));
        IBeaconProxyFactory(withdrawals.bagFactory)
            .initialize(_registryValue(RegistryKeys.BAG), timelock, withdrawals.withdrawalRequest, timelock);

        withdrawals.requestPolicy = address(new MinAmountRequestPolicy(minWithdrawalAmount));

        IWithdrawalRequest(withdrawals.withdrawalRequest)
            .initialize(
                vault,
                timelock,
                resolver,
                timelock,
                pauser,
                withdrawals.bagFactory,
                withdrawals.withdrawer,
                withdrawals.requestPolicy,
                maxDataLength
            );

        emit WithdrawalSystemDeployed(vault, timelock, withdrawals);
    }

    function _bootstrap(IVault vault, VaultParams calldata params) internal {
        IERC20 asset = IERC20(params.baseAsset);
        asset.safeTransferFrom(msg.sender, address(this), params.bootstrapAmount);
        asset.forceApprove(address(vault), params.bootstrapAmount);
        vault.unpause();
        vault.deposit(params.bootstrapAmount, params.bootstrapReceiver);
        asset.forceApprove(address(vault), 0);
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
}
