// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";

contract CreateVault is Script {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice Receives every vault role, the timelock proposer/executor seat, and the bootstrap shares.
    address internal constant CONTROLLER = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    /// @notice Ethereum mainnet USDC, used as both base and default asset.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant OFF_RAMP = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;

    uint256 internal constant TIMELOCK_DURATION = 30 seconds;
    // 0.1 USDC expressed in 18-decimal vault shares, the unit the request policy locks.
    uint256 internal constant MIN_WITHDRAWAL_AMOUNT = 0.1 ether;
    uint256 internal constant MAX_DATA_LENGTH = 256;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6; // 1 USDC
    uint256 internal constant TARGET_APY = 0.05e18;
    uint256 internal constant LOWER_BOUND = 0.01e18;
    uint256 internal constant MIN_REWARDABLE_ASSETS = 100e6;

    function run() external returns (IVaultFactory.CreatedVault memory created) {
        address factory = vm.promptAddress("VaultFactory address");

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            admin: CONTROLLER,
            processor: CONTROLLER,
            pauser: CONTROLLER,
            unpauser: CONTROLLER,
            feeManager: CONTROLLER,
            resolver: CONTROLLER,
            baseAsset: USDC,
            tokenName: "Whitelabel USDC RWA",
            tokenSymbol: "WLRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: TIMELOCK_DURATION,
            minWithdrawalAmount: MIN_WITHDRAWAL_AMOUNT,
            maxDataLength: MAX_DATA_LENGTH,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: CONTROLLER
        });

        IVaultFactory.FlexStrategyParams memory flexParams = IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: CONTROLLER,
            offRampAddress: OFF_RAMP,
            accountingProcessor: CONTROLLER,
            targetApy: TARGET_APY,
            lowerBound: LOWER_BOUND,
            minRewardableAssets: MIN_REWARDABLE_ASSETS,
            strategyName: "Whitelabel USDC Flex Strategy",
            strategySymbol: "WLFUSDC-FLEX",
            accountingTokenName: "Whitelabel USDC Flex Accounting",
            accountingTokenSymbol: "aWLFUSDC"
        });

        vm.startBroadcast();
        (bytes32 deploymentId, IVaultFactory.CreatedVault memory started) =
            IVaultFactory(factory).startCreateVault(params, flexParams);
        IERC20(USDC).approve(factory, BOOTSTRAP_AMOUNT * 2);
        created = IVaultFactory(factory).resumeCreateVault(deploymentId);
        vm.stopBroadcast();

        console2.logBytes32(deploymentId);
        console2.log("Started vault:", started.vault);
        console2.log("Vault:", created.vault);
        console2.log("Timelock:", created.timelock);
        console2.log("Wrapped token:", created.wrappedToken);
        console2.log("Provider:", created.provider);
        console2.log("Withdrawal request:", created.withdrawalRequest);
        console2.log("Withdrawer:", created.withdrawer);
        console2.log("Bag factory:", created.bagFactory);
        console2.log("Request policy:", created.requestPolicy);
        console2.log("SafeGuard:", created.safeGuard);
        console2.log("Accounting module hook:", created.accountingModuleHook);
        console2.log("Flex strategy:", created.flexStrategy);
        console2.log("Accounting token:", created.accountingToken);
        console2.log("Accounting module:", created.accountingModule);
        console2.log("Rewards sweeper:", created.rewardsSweeper);

        string memory obj = "deployment";
        vm.serializeBytes32(obj, "deploymentId", deploymentId);
        vm.serializeAddress(obj, "vault", created.vault);
        vm.serializeAddress(obj, "vaultProxyAdmin", _proxyAdmin(created.vault));
        vm.serializeAddress(obj, "timelock", created.timelock);
        vm.serializeAddress(obj, "wrappedToken", created.wrappedToken);
        vm.serializeAddress(obj, "wrappedTokenProxyAdmin", _proxyAdmin(created.wrappedToken));
        vm.serializeAddress(obj, "provider", created.provider);
        vm.serializeAddress(obj, "withdrawalRequest", created.withdrawalRequest);
        vm.serializeAddress(obj, "withdrawalRequestProxyAdmin", _proxyAdmin(created.withdrawalRequest));
        vm.serializeAddress(obj, "withdrawer", created.withdrawer);
        vm.serializeAddress(obj, "withdrawerProxyAdmin", _proxyAdmin(created.withdrawer));
        vm.serializeAddress(obj, "bagFactory", created.bagFactory);
        vm.serializeAddress(obj, "bagFactoryProxyAdmin", _proxyAdmin(created.bagFactory));
        vm.serializeAddress(obj, "withdrawalRequestViewer", RegistryImplementations.WITHDRAWAL_REQUEST_VIEWER);
        vm.serializeAddress(obj, "safeGuard", created.safeGuard);
        vm.serializeAddress(obj, "safeGuardProxyAdmin", _proxyAdmin(created.safeGuard));
        vm.serializeAddress(obj, "accountingModuleHook", created.accountingModuleHook);
        vm.serializeAddress(obj, "flexStrategy", created.flexStrategy);
        vm.serializeAddress(obj, "flexStrategyProxyAdmin", _proxyAdmin(created.flexStrategy));
        vm.serializeAddress(obj, "accountingToken", created.accountingToken);
        vm.serializeAddress(obj, "accountingTokenProxyAdmin", _proxyAdmin(created.accountingToken));
        vm.serializeAddress(obj, "accountingModule", created.accountingModule);
        vm.serializeAddress(obj, "accountingModuleProxyAdmin", _proxyAdmin(created.accountingModule));
        vm.serializeAddress(obj, "rewardsSweeper", created.rewardsSweeper);
        vm.serializeAddress(obj, "rewardsSweeperProxyAdmin", _proxyAdmin(created.rewardsSweeper));
        string memory json = vm.serializeAddress(obj, "requestPolicy", created.requestPolicy);

        vm.createDir("deployments", true);
        string memory path = string.concat("deployments/rwa-vault-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment written to:", path);
    }

    function _proxyAdmin(address proxy) internal view returns (address) {
        if (proxy == address(0)) return address(0);
        return address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
    }
}
