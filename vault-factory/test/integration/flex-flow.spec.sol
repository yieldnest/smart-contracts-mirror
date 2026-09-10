// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";
import {SafeTestLib} from "test/lib/SafeTestLib.sol";
import {TestConstants} from "test/lib/TestConstants.sol";
import {ISafe} from "lib/safeguard/lib/safe-smart-account/contracts/interfaces/ISafe.sol";
import {IGuardManager} from "lib/safeguard/lib/safe-smart-account/contracts/interfaces/IGuardManager.sol";

interface IVaultFlow {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}

interface IStrategyFlow {
    function accountingModule() external view returns (address);
    function hooks() external view returns (address);
}

interface IAccountingModuleFlow {
    function safe() external view returns (address);
    function accountingToken() external view returns (address);
}

contract VaultFactoryFlexFlowIntegrationTest is Test {
    uint256 private constant BOOTSTRAP_AMOUNT = 1e6;
    uint256 private constant MIN_DEPOSIT_AMOUNT = 1e6;
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1_000_000e6;

    IRegistry private registry;
    VaultFactory private factory;
    ISafe private safe;
    IVaultFactory.CreatedVault private created;

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        vm.skip(bytes(rpcUrl).length == 0, "MAINNET_RPC_URL not set");
        vm.createSelectFork(rpcUrl);

        registry = _deployRegistry();
        _populateRegistry();
        factory = new VaultFactory(registry);
        safe = SafeTestLib.deploySingleOwnerSafe(TestConstants.SAFE_OWNER);

        deal(TestConstants.USDC, TestConstants.CREATOR, BOOTSTRAP_AMOUNT * 2);

        vm.startPrank(TestConstants.CREATOR);
        IERC20(TestConstants.USDC).approve(address(factory), BOOTSTRAP_AMOUNT * 2);
        created = factory.createVault(_vaultParams(), _flexParams(address(safe)));
        vm.stopPrank();
    }

    function testFuzz_Flex_Deposit_Processor_Move_And_Guarded_OffRamp(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, MIN_DEPOSIT_AMOUNT, MAX_DEPOSIT_AMOUNT);

        assertEq(IStrategyFlow(created.flexStrategy).hooks(), created.accountingModuleHook, "strategy hook");
        assertEq(IStrategyFlow(created.flexStrategy).accountingModule(), created.accountingModule, "accounting module");
        assertEq(IAccountingModuleFlow(created.accountingModule).safe(), address(safe), "accounting safe");

        SafeTestLib.execSingleOwnerSafeTransaction(
            safe,
            TestConstants.SAFE_OWNER,
            address(safe),
            abi.encodeWithSelector(IGuardManager.setGuard.selector, created.safeGuard)
        );

        uint256 safeBalanceAfterBootstrap = IERC20(TestConstants.USDC).balanceOf(address(safe));
        assertEq(safeBalanceAfterBootstrap, BOOTSTRAP_AMOUNT, "bootstrap moved to safe");
        assertEq(
            IERC20(TestConstants.USDC).balanceOf(created.flexStrategy), 0, "strategy does not custody USDC after hook"
        );
        assertEq(IERC20(created.accountingToken).balanceOf(created.flexStrategy), BOOTSTRAP_AMOUNT, "bootstrap IOU");

        deal(TestConstants.USDC, TestConstants.DEPOSITOR, depositAmount);
        vm.startPrank(TestConstants.DEPOSITOR);
        IERC20(TestConstants.USDC).approve(created.vault, depositAmount);
        IVaultFlow(created.vault).deposit(depositAmount, TestConstants.DEPOSITOR);
        vm.stopPrank();

        assertEq(
            IERC20(TestConstants.USDC).balanceOf(created.vault), BOOTSTRAP_AMOUNT + depositAmount, "vault holds deposit"
        );
        assertEq(
            IERC20(TestConstants.USDC).balanceOf(address(safe)),
            safeBalanceAfterBootstrap,
            "safe unchanged before processor"
        );

        _moveVaultAssetsToFlexStrategy(depositAmount);

        assertEq(IERC20(TestConstants.USDC).balanceOf(created.vault), BOOTSTRAP_AMOUNT, "vault USDC allocated");
        assertEq(IERC20(TestConstants.USDC).balanceOf(created.flexStrategy), 0, "hook emptied strategy USDC");
        assertEq(
            IERC20(TestConstants.USDC).balanceOf(address(safe)),
            safeBalanceAfterBootstrap + depositAmount,
            "safe received processor allocation"
        );
        assertEq(
            IERC20(created.accountingToken).balanceOf(created.flexStrategy),
            BOOTSTRAP_AMOUNT + depositAmount,
            "accounting token minted to strategy"
        );
        assertEq(IERC20(created.flexStrategy).balanceOf(created.vault), BOOTSTRAP_AMOUNT + depositAmount, "shares");

        SafeTestLib.execSingleOwnerSafeTransaction(
            safe,
            TestConstants.SAFE_OWNER,
            TestConstants.USDC,
            abi.encodeCall(IERC20.transfer, (TestConstants.OFF_RAMP, depositAmount))
        );

        assertEq(IERC20(TestConstants.USDC).balanceOf(TestConstants.OFF_RAMP), depositAmount, "off-ramp funded");
        assertEq(IERC20(TestConstants.USDC).balanceOf(address(safe)), safeBalanceAfterBootstrap, "safe debited");
    }

    function _moveVaultAssetsToFlexStrategy(uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = TestConstants.USDC;
        targets[1] = created.flexStrategy;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IERC20.approve, (created.flexStrategy, amount));
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, created.vault);

        vm.prank(TestConstants.PROCESSOR);
        IVaultFlow(created.vault).processor(targets, values, data);
    }

    function _deployRegistry() internal returns (IRegistry deployedRegistry) {
        Registry registryLogic = new Registry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryLogic), address(this), abi.encodeCall(IRegistry.initialize, (address(this)))
        );
        deployedRegistry = IRegistry(address(registryProxy));
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
            tokenName: "Whitelabel Flex USDC",
            tokenSymbol: "WLFUSDC",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 30 seconds,
            minWithdrawalAmount: 0.1 ether,
            maxDataLength: 256,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: TestConstants.BOOTSTRAP_RECEIVER
        });
    }

    function _flexParams(address multisig) internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            multisig: multisig,
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
}
