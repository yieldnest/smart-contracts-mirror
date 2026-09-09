// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";

interface IUpgradeableBeaconFactoryView {
    function implementation() external view returns (address);
    function upgradeImplementation(address newImplementation) external;
}

contract UpgradeTarget {}

contract VaultFactoryUpgradeabilityIntegrationTest is Test {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 private constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant ADMIN = 0x0e46F77dbe0b6e9782bDe5596cdAb025C222cC5d;
    address private constant PROCESSOR = 0x1000000000000000000000000000000000000001;
    address private constant PAUSER = 0x1000000000000000000000000000000000000002;
    address private constant UNPAUSER = 0x1000000000000000000000000000000000000003;
    address private constant FEE_MANAGER = 0x1000000000000000000000000000000000000004;
    address private constant RESOLVER = 0x1000000000000000000000000000000000000005;
    address private constant BOOTSTRAP_RECEIVER = 0x1000000000000000000000000000000000000006;
    address private constant CREATOR = 0x1000000000000000000000000000000000000007;

    uint256 private constant BOOTSTRAP_AMOUNT = 1e6;

    IRegistry internal registry;
    VaultFactory internal factory;
    IVaultFactory.CreatedVault internal created;

    function setUp() public virtual {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpcUrl).length == 0, "MAINNET_RPC_URL not set");
        vm.createSelectFork(rpcUrl);

        registry = _deployRegistry();
        _populateRegistry();
        factory = new VaultFactory(registry);

        deal(USDC, CREATOR, BOOTSTRAP_AMOUNT);

        vm.startPrank(CREATOR);
        IERC20(USDC).approve(address(factory), BOOTSTRAP_AMOUNT);
        created = factory.createVault(_vaultParams(), _emptyFlexParams());
        vm.stopPrank();
    }

    function test_CreateVault_Upgradeable_Contracts_Can_Be_Upgraded_Through_Timelock() public {
        address vaultImplementation = address(new UpgradeTarget());
        address wrappedTokenImplementation = address(new UpgradeTarget());
        address withdrawalRequestImplementation = address(new UpgradeTarget());
        address withdrawerImplementation = address(new UpgradeTarget());
        address bagFactoryImplementation = address(new UpgradeTarget());
        address bagImplementation = address(new UpgradeTarget());

        _timelockUpgradeProxy(created.vault, vaultImplementation, "vault");
        _timelockUpgradeProxy(created.wrappedToken, wrappedTokenImplementation, "wrapped token");
        _timelockUpgradeProxy(created.withdrawalRequest, withdrawalRequestImplementation, "withdrawal request");
        _timelockUpgradeProxy(created.withdrawer, withdrawerImplementation, "withdrawer");
        _timelockUpgradeBagImplementation(bagImplementation);
        _timelockUpgradeProxy(created.bagFactory, bagFactoryImplementation, "bag factory");
    }

    function _deployRegistry() internal returns (IRegistry) {
        Registry registryLogic = new Registry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryLogic), address(this), abi.encodeCall(IRegistry.initialize, (address(this)))
        );

        return IRegistry(address(registryProxy));
    }

    function _populateRegistry() internal {
        bytes32[] memory keys = new bytes32[](6);
        keys[0] = RegistryKeys.VAULT;
        keys[1] = RegistryKeys.WRAPPED_TOKEN;
        keys[2] = RegistryKeys.WITHDRAWAL_REQUEST;
        keys[3] = RegistryKeys.WITHDRAWER;
        keys[4] = RegistryKeys.BAG_FACTORY;
        keys[5] = RegistryKeys.BAG;

        address[] memory values = new address[](6);
        values[0] = RegistryImplementations.VAULT_IMPLEMENTATION;
        values[1] = RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION;
        values[2] = RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION;
        values[3] = RegistryImplementations.WITHDRAWER_IMPLEMENTATION;
        values[4] = RegistryImplementations.BAG_FACTORY_IMPLEMENTATION;
        values[5] = RegistryImplementations.BAG_IMPLEMENTATION;

        registry.setValues(keys, values);
    }

    function _vaultParams() internal pure returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: ADMIN,
            processor: PROCESSOR,
            pauser: PAUSER,
            unpauser: UNPAUSER,
            feeManager: FEE_MANAGER,
            resolver: RESOLVER,
            baseAsset: USDC,
            tokenName: "Whitelabel USDC RWA",
            tokenSymbol: "WLRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 30 seconds,
            minWithdrawalAmount: 0.1 ether,
            maxDataLength: 256,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: BOOTSTRAP_RECEIVER
        });
    }

    function _emptyFlexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory flexParams) {
        flexParams.deployStrategy = false;
    }

    function _timelockUpgradeProxy(address proxy, address newImplementation, string memory label) internal {
        assertTrue(_implementation(proxy) != newImplementation, string.concat(label, " precondition"));

        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
        bytes memory data = abi.encodeCall(
            ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(proxy), newImplementation, bytes(""))
        );
        _scheduleAndExecute(proxyAdmin, data, keccak256(abi.encode(label, proxy, newImplementation)));

        assertEq(_implementation(proxy), newImplementation, string.concat(label, " implementation"));
    }

    function _timelockUpgradeBagImplementation(address newImplementation) internal {
        IUpgradeableBeaconFactoryView bagFactory = IUpgradeableBeaconFactoryView(created.bagFactory);
        assertTrue(bagFactory.implementation() != newImplementation, "bag precondition");

        bytes memory data = abi.encodeCall(IUpgradeableBeaconFactoryView.upgradeImplementation, (newImplementation));
        _scheduleAndExecute(
            created.bagFactory, data, keccak256(abi.encode("bag", created.bagFactory, newImplementation))
        );

        assertEq(bagFactory.implementation(), newImplementation, "bag implementation");
    }

    function _scheduleAndExecute(address target, bytes memory data, bytes32 salt) internal {
        TimelockController timelock = TimelockController(payable(created.timelock));
        uint256 delay = timelock.getMinDelay();

        vm.prank(ADMIN);
        timelock.schedule(target, 0, data, bytes32(0), salt, delay);

        vm.warp(block.timestamp + delay);

        vm.prank(ADMIN);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }
}
