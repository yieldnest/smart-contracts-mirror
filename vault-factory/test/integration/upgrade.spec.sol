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
import {TestConstants} from "test/lib/TestConstants.sol";

interface IUpgradeableBeaconFactoryView {
    function implementation() external view returns (address);
    function upgradeImplementation(address newImplementation) external;
}

contract UpgradeTarget {}

contract VaultFactoryUpgradeabilityIntegrationTest is Test {
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

        deal(TestConstants.USDC, TestConstants.CREATOR, BOOTSTRAP_AMOUNT * 2);

        vm.startPrank(TestConstants.CREATOR);
        IERC20(TestConstants.USDC).approve(address(factory), BOOTSTRAP_AMOUNT * 2);
        created = factory.createVault(_vaultParams(), _flexParams());
        vm.stopPrank();
    }

    function test_CreateVault_Upgradeable_Contracts_Can_Be_Upgraded_Through_Timelock() public {
        address vaultImplementation = address(new UpgradeTarget());
        address wrappedTokenImplementation = address(new UpgradeTarget());
        address withdrawalRequestImplementation = address(new UpgradeTarget());
        address withdrawerImplementation = address(new UpgradeTarget());
        address bagFactoryImplementation = address(new UpgradeTarget());
        address bagImplementation = address(new UpgradeTarget());
        address safeGuardImplementation = address(new UpgradeTarget());
        address flexStrategyImplementation = address(new UpgradeTarget());
        address accountingTokenImplementation = address(new UpgradeTarget());
        address accountingModuleImplementation = address(new UpgradeTarget());
        address rewardsSweeperImplementation = address(new UpgradeTarget());

        _timelockUpgradeProxy(created.vault, vaultImplementation, "vault");
        _timelockUpgradeProxy(created.wrappedToken, wrappedTokenImplementation, "wrapped token");
        _timelockUpgradeProxy(created.withdrawalRequest, withdrawalRequestImplementation, "withdrawal request");
        _timelockUpgradeProxy(created.withdrawer, withdrawerImplementation, "withdrawer");
        _timelockUpgradeBagImplementation(bagImplementation);
        _timelockUpgradeProxy(created.bagFactory, bagFactoryImplementation, "bag factory");
        _timelockUpgradeProxy(created.safeGuard, safeGuardImplementation, "safeguard");
        _timelockUpgradeProxy(created.flexStrategy, flexStrategyImplementation, "flex strategy");
        _timelockUpgradeProxy(created.accountingToken, accountingTokenImplementation, "accounting token");
        _timelockUpgradeProxy(created.accountingModule, accountingModuleImplementation, "accounting module");
        _timelockUpgradeProxy(created.rewardsSweeper, rewardsSweeperImplementation, "rewards sweeper");
    }

    function test_CreateVault_NonUpgradeable_Flex_Helper_Contracts_Are_Deployed() public view {
        assertGt(created.accountingModuleHook.code.length, 0, "accounting module hook code");
        assertEq(_implementation(created.accountingModuleHook), address(0), "hook is not erc1967 proxy");

        address hooksDeployer = registry.valueOf(RegistryKeys.HOOKS_DEPLOYER);
        assertGt(hooksDeployer.code.length, 0, "hooks deployer code");
        assertEq(_implementation(hooksDeployer), address(0), "hooks deployer is not erc1967 proxy");
    }

    function _deployRegistry() internal returns (IRegistry) {
        Registry registryLogic = new Registry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryLogic), address(this), abi.encodeCall(IRegistry.initialize, (address(this)))
        );

        return IRegistry(address(registryProxy));
    }

    function _populateRegistry() internal {
        bytes32[] memory keys = new bytes32[](12);
        keys[0] = RegistryKeys.VAULT;
        keys[1] = RegistryKeys.WRAPPED_TOKEN;
        keys[2] = RegistryKeys.WITHDRAWAL_REQUEST;
        keys[3] = RegistryKeys.WITHDRAWER;
        keys[4] = RegistryKeys.BAG_FACTORY;
        keys[5] = RegistryKeys.BAG;
        keys[6] = RegistryKeys.FLEX_STRATEGY;
        keys[7] = RegistryKeys.ACCOUNTING_MODULE;
        keys[8] = RegistryKeys.ACCOUNTING_TOKEN_FACTORY;
        keys[9] = RegistryKeys.REWARDS_SWEEPER;
        keys[10] = RegistryKeys.SAFE_GUARD;
        keys[11] = RegistryKeys.HOOKS_DEPLOYER;

        address[] memory values = new address[](12);
        values[0] = RegistryImplementations.VAULT_IMPLEMENTATION;
        values[1] = RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION;
        values[2] = RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION;
        values[3] = RegistryImplementations.WITHDRAWER_IMPLEMENTATION;
        values[4] = RegistryImplementations.BAG_FACTORY_IMPLEMENTATION;
        values[5] = RegistryImplementations.BAG_IMPLEMENTATION;
        values[6] = RegistryImplementations.FLEX_STRATEGY_IMPLEMENTATION;
        values[7] = RegistryImplementations.ACCOUNTING_MODULE_IMPLEMENTATION;
        values[8] = RegistryImplementations.ACCOUNTING_TOKEN_FACTORY_IMPLEMENTATION;
        values[9] = RegistryImplementations.REWARDS_SWEEPER_IMPLEMENTATION;
        values[10] = RegistryImplementations.SAFE_GUARD_IMPLEMENTATION;
        values[11] = RegistryImplementations.HOOKS_DEPLOYER;

        registry.setValues(keys, values);
    }

    function _vaultParams() internal pure returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: TestConstants.ADMIN,
            processor: TestConstants.PROCESSOR,
            pauser: TestConstants.PAUSER,
            unpauser: TestConstants.UNPAUSER,
            feeManager: TestConstants.FEE_MANAGER,
            resolver: TestConstants.RESOLVER,
            baseAsset: TestConstants.USDC,
            tokenName: "Whitelabel USDC RWA",
            tokenSymbol: "WLRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 30 seconds,
            minWithdrawalAmount: 0.1 ether,
            maxDataLength: 256,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: TestConstants.BOOTSTRAP_RECEIVER
        });
    }

    function _flexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            alwaysComputeTotalAssets: true,
            multisig: TestConstants.SAFE_OWNER,
            offRampAddress: TestConstants.OFF_RAMP,
            accountingProcessor: TestConstants.PROCESSOR,
            targetApy: 0.05e18,
            lowerBound: 0.01e18,
            minRewardableAssets: 100e6,
            strategyName: "Flex Strategy",
            strategySymbol: "FLEX",
            accountingTokenName: "Flex Accounting",
            accountingTokenSymbol: "aFLEX"
        });
    }

    function _timelockUpgradeProxy(address proxy, address newImplementation, string memory label) internal {
        assertTrue(_implementation(proxy) != newImplementation, string.concat(label, " precondition"));

        address proxyAdmin = address(uint160(uint256(vm.load(proxy, TestConstants.ERC1967_ADMIN_SLOT))));
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

        vm.prank(TestConstants.ADMIN);
        timelock.schedule(target, 0, data, bytes32(0), salt, delay);

        vm.warp(block.timestamp + delay);

        vm.prank(TestConstants.ADMIN);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, TestConstants.ERC1967_IMPLEMENTATION_SLOT))));
    }
}
