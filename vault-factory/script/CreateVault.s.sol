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

    uint256 internal constant TIMELOCK_DURATION = 30 seconds;
    // 0.1 USDC expressed in 18-decimal vault shares, the unit the request policy locks.
    uint256 internal constant MIN_WITHDRAWAL_AMOUNT = 0.1 ether;
    uint256 internal constant MAX_DATA_LENGTH = 256;
    uint256 internal constant BOOTSTRAP_AMOUNT = 1e6; // 1 USDC

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
            deployStrategy: false, multisig: address(0), offRampAddress: address(0), deployData: ""
        });

        vm.startBroadcast();
        IERC20(USDC).approve(factory, BOOTSTRAP_AMOUNT);
        created = IVaultFactory(factory).createVault(params, flexParams);
        vm.stopBroadcast();

        console2.log("Vault:", created.vault);
        console2.log("Timelock:", created.timelock);
        console2.log("Wrapped token:", created.wrappedToken);
        console2.log("Provider:", created.provider);
        console2.log("Withdrawal request:", created.withdrawalRequest);
        console2.log("Withdrawer:", created.withdrawer);
        console2.log("Bag factory:", created.bagFactory);
        console2.log("Request policy:", created.requestPolicy);

        string memory obj = "deployment";
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
