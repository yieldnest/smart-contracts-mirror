// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IActors} from "lib/yieldnest-vault/script/Actors.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/yieldnest-vault/src/Common.sol";
import {BaseRoles} from "script/roles/BaseRoles.sol";
import {SafeRules, IVault} from "@yieldnest-vault-script/rules/SafeRules.sol";
import {Provider} from "src/module/Provider.sol";
import {ERC4626WrapperHooks} from "src/hooks/ERC4626WrapperHooks.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {BaseRules} from "lib/yieldnest-vault/script/rules/BaseRules.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20Metadata} from "lib/yieldnest-vault/src/Common.sol";
import {SingleAssetProvider} from "src/module/SingleAssetProvider.sol";
import {IHooksFactory} from "src/interfaces/IHooksFactory.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IMetaHooks} from "src/interfaces/IMetaHooks.sol";

contract StrategyDeployer {
    error InvalidDeploymentParams(string);
    error DeploymentDone();

    struct DeploymentParams {
        string name;
        string symbol;
        uint8 decimals;
        IActors actors;
        address baseAsset;
        address targetVault;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint64 baseWithdrawalFee;
        Implementations implementations;
    }

    struct Implementations {
        ERC4626WrapperStrategy stakedLpStrategyImplementation;
        TimelockController timelockController;
        IHooksFactory hooksFactory;
        Provider provider;
    }

    ERC4626WrapperStrategy public strategy;

    address public deployer;
    string public name;
    string public symbol_;
    uint8 public decimals;
    bool public countNativeAsset;
    bool public alwaysComputeTotalAssets;
    IProvider public rateProvider;
    TimelockController public timelock;
    IActors internal actors;
    Implementations internal implementations;
    address public baseAsset;
    address public targetVault;
    address public curvePool;
    uint64 public baseWithdrawalFee;
    bool public deploymentDone;

    constructor(DeploymentParams memory params) {
        // the contract is the deployer
        deployer = address(this);
        actors = params.actors;

        // Set deployment parameters
        name = params.name;
        symbol_ = params.symbol;
        decimals = params.decimals;
        baseAsset = params.baseAsset;
        targetVault = params.targetVault;
        countNativeAsset = params.countNativeAsset;
        alwaysComputeTotalAssets = params.alwaysComputeTotalAssets;
        baseWithdrawalFee = params.baseWithdrawalFee;
        implementations = params.implementations;
    }

    function deploy() public virtual {
        if (deploymentDone) {
            revert DeploymentDone();
        }
        deploymentDone = true;

        address admin = deployer;

        timelock = implementations.timelockController;

        deployRateProvider();

        // Adapt initialization to match StakedLPStrategy.InitParams
        // See StakedLPStrategy.sol for the correct order/fields.
        strategy = ERC4626WrapperStrategy(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(implementations.stakedLpStrategyImplementation),
                        address(timelock),
                        abi.encodeWithSelector(
                            ERC4626WrapperStrategy.initialize.selector,
                            // Pass as a single InitParams struct as required in StakedLPStrategy
                            ERC4626WrapperStrategy.InitParams({
                                admin: admin,
                                name: name,
                                symbol: symbol_,
                                decimals_: decimals,
                                alwaysComputeTotalAssets_: alwaysComputeTotalAssets, // for fee collection
                                defaultAssetIndex_: 0,
                                countNativeAsset_: countNativeAsset
                            })
                        )
                    )
                )
            )
        );

        configureStrategy();
    }

    function configureStrategy() internal virtual {
        BaseRoles.configureDefaultRolesStrategy(strategy, address(timelock), actors);
        BaseRoles.configureTemporaryRolesStrategy(strategy, deployer);

        strategy.grantRole(strategy.FEE_MANAGER_ROLE(), actors.FEE_MANAGER());

        address underlyingAsset;
        if (!targetVaultIsSet()) {
            underlyingAsset = baseAsset;
        } else {
            underlyingAsset = IERC4626(targetVault).asset();
            if (underlyingAsset != baseAsset) {
                revert InvalidDeploymentParams("baseAsset is not the underlying asset of the targetVault");
            }
        }

        {
            // depositable and withdrawable
            strategy.addAsset(underlyingAsset, IERC20Metadata(underlyingAsset).decimals(), true, true);
            // not depositable and not withdrawable
            if (targetVaultIsSet()) {
                strategy.addAsset(targetVault, false, false);
            }

            strategy.setProvider(address(rateProvider));
        }

        {
            address hooksOwner = address(this);
            IHooks[] memory emptyArray = new IHooks[](0);
            IMetaHooks metaHooks =
                implementations.hooksFactory.createMetaHooks(address(strategy), hooksOwner, hooksOwner, emptyArray);

            //  The vault is the strategy, but the caller is the metaHooks
            ERC4626WrapperHooks erc4626WrapperHooks =
                new ERC4626WrapperHooks(address(strategy), address(metaHooks), targetVault);

            IHooks feeHooks = implementations.hooksFactory.createFeeHooks(
                address(metaHooks), actors.ADMIN(), 0, actors.FEE_RECEIVER()
            );

            IHooks processAccountingGuardHook = implementations.hooksFactory.createProcessAccountingGuardHook(
                address(metaHooks), // 1: pass address(metaHooks) as the vault argument
                actors.ADMIN(), // 2: pass actors.ADMIN() as the owner argument
                0.001 ether, // 3: set maxDecreaseRatio to 0.001 ether (0.1%)
                0.002 ether, // 4: set maxIncreaseRatio to 0.002 ether (0.2%)
                0 ether, // 5: set maxTotalSupplyIncreaseRatio to 0%
                0 ether // 6: performanceFee is set to 0 ether
            );

            strategy.setHooks(address(metaHooks));

            // Use IMetaHooks interface directly, instead of AccessControl casting.

            metaHooks.grantRole(metaHooks.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
            metaHooks.grantRole(metaHooks.HOOK_MANAGER_ROLE(), actors.ADMIN());

            {
                address[] memory hooksArray = new address[](3);
                hooksArray[0] = address(erc4626WrapperHooks);
                hooksArray[1] = address(feeHooks);
                hooksArray[2] = address(processAccountingGuardHook);
                metaHooks.setHooks(hooksArray);

                // address[] memory hooksArray = new address[](1);
                // hooksArray[0] = address(erc4626WrapperHooks);
                // metaHooks.setHooks(hooksArray);
            }

            // renounce for deployer
            metaHooks.renounceRole(metaHooks.DEFAULT_ADMIN_ROLE(), address(this));
            metaHooks.renounceRole(metaHooks.HOOK_MANAGER_ROLE(), address(this));

            strategy.grantRole(strategy.PROCESSOR_ROLE(), address(erc4626WrapperHooks));
        }

        if (targetVaultIsSet()) {
            SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](3);
            rules[0] = BaseRules.getDepositRule(targetVault, address(strategy));
            rules[1] = BaseRules.getWithdrawRule(targetVault, address(strategy));
            rules[2] = BaseRules.getApprovalRule(underlyingAsset, targetVault);

            // Set processor rules using SafeRules
            SafeRules.setProcessorRules(IVault(address(strategy)), rules, true);
        }

        {
            strategy.grantRole(strategy.FEE_MANAGER_ROLE(), deployer);
            strategy.setBaseWithdrawalFee(baseWithdrawalFee);
            strategy.renounceRole(strategy.FEE_MANAGER_ROLE(), deployer);
        }

        strategy.unpause();

        BaseRoles.renounceTemporaryRolesStrategy(strategy, deployer);
    }

    function targetVaultIsSet() internal view returns (bool) {
        return targetVault != address(0);
    }

    function deployRateProvider() internal {
        rateProvider = IProvider(address(implementations.provider));
    }
}
