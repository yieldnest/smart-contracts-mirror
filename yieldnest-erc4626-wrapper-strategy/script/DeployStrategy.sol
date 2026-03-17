// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {console} from "forge-std/console.sol";
import {SafeRules, IVault} from "@yieldnest-vault-script/rules/SafeRules.sol";
import {StrategyDeployer} from "script/StrategyDeployer.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {Script} from "forge-std/Script.sol";
import {Provider} from "src/module/Provider.sol";
import {IHooksFactory} from "src/interfaces/IHooksFactory.sol";

// forge script DeployStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account
// <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>  --verify --etherscan-api-key <ETHERSCAN_API_KEY>  -vvv
contract DeployStrategy is BaseScript {
    error InvalidRules();
    error InvalidRateProvider();
    error InvalidDeploymentParams(string);

    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    function _verifySetup() public view override {
        super._verifySetup();
    }

    function createDeployer(StrategyDeployer.Implementations memory implementations)
        internal
        virtual
        returns (StrategyDeployer)
    {
        return new StrategyDeployer(
            StrategyDeployer.DeploymentParams({
                name: name,
                symbol: symbol_,
                decimals: decimals,
                actors: actors,
                baseAsset: baseAsset,
                targetVault: targetVault,
                countNativeAsset: countNativeAsset,
                alwaysComputeTotalAssets: alwaysComputeTotalAssets,
                baseWithdrawalFee: baseWithdrawalFee,
                implementations: implementations
            })
        );
    }

    function run() public virtual {
        vm.startBroadcast();

        _setup();
        assignDeploymentParameters();
        _verifyDeploymentParams();

        _deployTimelockController();

        StrategyDeployer.Implementations memory implementations;
        implementations.stakedLpStrategyImplementation = new ERC4626WrapperStrategy();
        implementations.timelockController = timelock;
        implementations.hooksFactory = IHooksFactory(0x030cA515342C7d5DD20CeaD9c9817a7279F23e63);
        implementations.provider = new Provider(targetVault, 10 ** decimals);

        StrategyDeployer strategyDeployer = createDeployer(implementations);
        // The Deployer is the Strategy Deployer contract
        deployer = address(strategyDeployer);

        strategyDeployer.deploy();
        readDeployedContracts(strategyDeployer);

        _verifySetup();

        _saveDeployment(deploymentEnv);

        vm.stopBroadcast();
    }

    function readDeployedContracts(StrategyDeployer strategyDeployer) internal virtual {
        strategy = strategyDeployer.strategy();
        rateProvider = strategyDeployer.rateProvider();
        timelock = strategyDeployer.timelock();
    }

    function assignDeploymentParameters() internal virtual {
        if (decimals == 0) {
            revert("Not pre-configured");
        }
        if (!skipTargetVault) {
            if (baseAsset != IERC4626(targetVault).asset()) {
                revert InvalidDeploymentParams("baseAsset is not the underlying asset of the targetVault");
            }
        } else {
            if (baseAsset == address(0)) {
                revert InvalidDeploymentParams("baseAsset is not set");
            }
        }
    }

    function _verifyDeploymentParams() internal view virtual {
        if (bytes(name).length == 0) {
            revert InvalidDeploymentParams("strategy name not set");
        }

        if (bytes(symbol_).length == 0) {
            revert InvalidDeploymentParams("strategy symbol not set");
        }

        if (decimals == 0) {
            revert InvalidDeploymentParams("strategy decimals not set");
        }

        if (targetVault == address(0)) {
            revert InvalidDeploymentParams("targetVault is not set");
        }
    }
}
