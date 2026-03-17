// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {MainnetActors, IActors} from "@yieldnest-vault-script/Actors.sol";
import {IContracts, L1Contracts} from "@yieldnest-vault-script/Contracts.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {StrategyDeployer} from "script/StrategyDeployer.sol";
import {ProxyUtils} from "lib/yieldnest-vault/script/ProxyUtils.sol";
import {console} from "forge-std/console.sol";

abstract contract BaseScript is Script {
    using stdJson for string;

    enum Env {
        TEST,
        PROD
    }

    struct DeploymentParameters {
        string name;
        string symbol_;
        uint8 decimals;
        address baseAsset;
        address targetVault;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        bool skipTargetVault;
        uint64 baseWithdrawalFee;
    }

    function setDeploymentParameters(DeploymentParameters memory params) public virtual {
        name = params.name;
        symbol_ = params.symbol_;
        decimals = params.decimals;
        targetVault = params.targetVault;
        countNativeAsset = params.countNativeAsset;
        baseAsset = params.baseAsset;
        skipTargetVault = params.skipTargetVault;
        alwaysComputeTotalAssets = params.alwaysComputeTotalAssets;
        baseWithdrawalFee = params.baseWithdrawalFee;
    }

    Env public deploymentEnv = Env.PROD;

    string public name;
    string public symbol_;
    uint8 public decimals;
    address public targetVault;
    bool public countNativeAsset;
    bool public alwaysComputeTotalAssets;
    address public baseAsset;
    bool public skipTargetVault;
    uint64 public baseWithdrawalFee;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    address public deployer;
    TimelockController public timelock;
    IProvider public rateProvider;

    ERC4626WrapperStrategy public strategy;
    address public strategyProxyAdmin;

    error UnsupportedChain();
    error InvalidSetup(string);

    // needs to be overridden by child script
    function symbol() public view virtual returns (string memory);

    function setEnv(Env env) public {
        deploymentEnv = env;
    }

    function _setup() public virtual {
        if (block.chainid == 1) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new L1Contracts());
        }
    }

    function _verifySetup() public view virtual {
        if (block.chainid != 1) {
            revert UnsupportedChain();
        }
        if (address(actors) == address(0)) {
            revert InvalidSetup("actors not set");
        }
        if (address(contracts) == address(0)) {
            revert InvalidSetup("contracts not set");
        }
        if (address(timelock) == address(0)) {
            revert InvalidSetup("timelock not set");
        }
    }

    function _deployTimelockController() internal virtual {
        address[] memory proposers = new address[](1);
        proposers[0] = actors.PROPOSER_1();

        address[] memory executors = new address[](1);
        executors[0] = actors.EXECUTOR_1();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
    }

    function _loadDeployment(Env env) internal virtual {
        if (!vm.isFile(_deploymentFilePath(env))) {
            console.log("No deployment file found");
            return;
        }
        string memory jsonInput = vm.readFile(_deploymentFilePath(env));
        symbol_ = vm.parseJsonString(jsonInput, ".symbol");
        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        timelock = TimelockController(payable(address(vm.parseJsonAddress(jsonInput, ".timelock"))));
        rateProvider = IProvider(payable(address(vm.parseJsonAddress(jsonInput, ".rateProvider"))));
        targetVault = vm.parseJsonAddress(jsonInput, ".targetVault");

        strategy = ERC4626WrapperStrategy(
            payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy"))))
        );
        strategyProxyAdmin = address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxyAdmin")));
    }

    function _deploymentFilePath(Env env) internal view virtual returns (string memory) {
        if (env == Env.PROD) {
            return string.concat(
                vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json"
            );
        }

        return string.concat(
            vm.projectRoot(), "/deployments/", "test-", symbol(), "-", Strings.toString(block.chainid), ".json"
        );
    }

    function _saveDeployment(Env env) internal virtual {
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", deployer);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));
        vm.serializeAddress(symbol(), "targetVault", targetVault);
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(strategy));

        strategyProxyAdmin = ProxyUtils.getProxyAdmin(address(strategy));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxyAdmin"), strategyProxyAdmin);

        string memory jsonOutput = symbol(); // For vm.writeJson only needs the key

        vm.writeJson(vm.serializeString(jsonOutput, "symbol", symbol()), _deploymentFilePath(env));
    }
}
