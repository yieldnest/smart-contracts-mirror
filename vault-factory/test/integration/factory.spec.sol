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
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";
import {RegistryImplementations} from "script/RegistryImplementations.sol";

interface IProxyAdminOwner {
    function owner() external view returns (address);
}

interface IVaultView {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function PROCESSOR_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function UNPAUSER_ROLE() external view returns (bytes32);
    function PROVIDER_MANAGER_ROLE() external view returns (bytes32);
    function BUFFER_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_MANAGER_ROLE() external view returns (bytes32);
    function PROCESSOR_MANAGER_ROLE() external view returns (bytes32);
    function HOOKS_MANAGER_ROLE() external view returns (bytes32);
    function FEE_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_WITHDRAWER_ROLE() external view returns (bytes32);

    function VAULT_VERSION() external view returns (string memory);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function defaultAssetIndex() external view returns (uint256);
    function countNativeAsset() external view returns (bool);
    function alwaysComputeTotalAssets() external view returns (bool);
    function baseWithdrawalFee() external view returns (uint64);
    function provider() external view returns (address);
    function buffer() external view returns (address);
    function paused() external view returns (bool);
    function getAssets() external view returns (address[] memory);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IWrappedTokenView {
    function asset() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function decimalsOffset() external view returns (uint8);
}

interface IWithdrawalRequestView {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function RESOLVER_ROLE() external view returns (bytes32);
    function CONFIGURATION_MANAGER_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);

    function token() external view returns (address);
    function bagFactory() external view returns (address);
    function withdrawer() external view returns (address);
    function requestPolicy() external view returns (address);
    function maxDataLength() external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IWithdrawerView {
    function token() external view returns (address);
    function withdrawalRequest() external view returns (address);
}

interface IBeaconProxyFactoryView {
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function CREATOR_ROLE() external view returns (bytes32);
    function IMPLEMENTATION_MANAGER_ROLE() external view returns (bytes32);

    function implementation() external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IRequestPolicyView {
    function minWithdrawalAmount() external view returns (uint256);
}

contract VaultFactoryIntegrationTest is Test {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

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
    uint256 private constant BOOTSTRAP_SHARES = 1e18;
    uint256 private constant MIN_WITHDRAWAL_AMOUNT = 0.1 ether;
    uint256 private constant MAX_DATA_LENGTH = 256;

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

    function test_Factory_Registry_Values_Set_Correctly() public view {
        assertEq(factory.VERSION(), "0.1.0", "factory version");
        assertEq(address(factory.REGISTRY()), address(registry), "factory registry");

        assertEq(registry.valueOf(RegistryKeys.VAULT), RegistryImplementations.VAULT_IMPLEMENTATION, "vault impl");
        assertEq(
            registry.valueOf(RegistryKeys.WRAPPED_TOKEN),
            RegistryImplementations.WRAPPED_TOKEN_IMPLEMENTATION,
            "wrapped token impl"
        );
        assertEq(
            registry.valueOf(RegistryKeys.WITHDRAWAL_REQUEST),
            RegistryImplementations.WITHDRAWAL_REQUEST_IMPLEMENTATION,
            "withdrawal request impl"
        );
        assertEq(
            registry.valueOf(RegistryKeys.WITHDRAWER),
            RegistryImplementations.WITHDRAWER_IMPLEMENTATION,
            "withdrawer impl"
        );
        assertEq(
            registry.valueOf(RegistryKeys.BAG_FACTORY),
            RegistryImplementations.BAG_FACTORY_IMPLEMENTATION,
            "bag factory impl"
        );
        assertEq(registry.valueOf(RegistryKeys.BAG), RegistryImplementations.BAG_IMPLEMENTATION, "bag impl");
    }

    function test_CreateVault_ERC20_And_ERC4626_View_Functions() public view {
        IVaultView vault = IVaultView(created.vault);

        assertEq(vault.name(), "Whitelabel USDC RWA", "vault name");
        assertEq(vault.symbol(), "WLRWA", "vault symbol");
        assertEq(vault.decimals(), 18, "vault decimals");
        assertEq(vault.VAULT_VERSION(), "0.4.2", "vault version");
        assertEq(vault.totalSupply(), BOOTSTRAP_SHARES, "total supply");
        assertEq(vault.balanceOf(BOOTSTRAP_RECEIVER), BOOTSTRAP_SHARES, "bootstrap shares");

        assertEq(vault.asset(), USDC, "default asset");
        assertEq(vault.totalAssets(), BOOTSTRAP_AMOUNT, "total assets");
        assertEq(vault.convertToShares(BOOTSTRAP_AMOUNT), BOOTSTRAP_SHARES, "convert to shares");
        assertEq(vault.convertToAssets(BOOTSTRAP_SHARES), BOOTSTRAP_AMOUNT, "convert to assets");
        assertGt(vault.maxDeposit(address(this)), 0, "max deposit");
        assertGt(vault.maxMint(address(this)), 0, "max mint");
        assertEq(vault.maxWithdraw(address(this)), 0, "max withdraw");
        assertEq(vault.maxRedeem(address(this)), 0, "max redeem");

        assertEq(vault.defaultAssetIndex(), 1, "default asset index");
        assertFalse(vault.countNativeAsset(), "count native asset");
        assertTrue(vault.alwaysComputeTotalAssets(), "always compute total assets");
        assertEq(vault.baseWithdrawalFee(), 0, "withdrawal fee");
        assertEq(vault.provider(), created.provider, "provider");
        assertEq(vault.buffer(), address(0), "buffer");
        assertFalse(vault.paused(), "paused");

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 2, "assets length");
        assertEq(assets[0], created.wrappedToken, "base asset wrapper");
        assertEq(assets[1], USDC, "default asset");
    }

    function test_CreateVault_Wrapper_And_Provider_Set_Correctly() public view {
        IWrappedTokenView wrappedToken = IWrappedTokenView(created.wrappedToken);
        assertEq(wrappedToken.asset(), USDC, "wrapped asset");
        assertEq(wrappedToken.name(), "Wrapped USD Coin", "wrapped name");
        assertEq(wrappedToken.symbol(), "WUSDC", "wrapped symbol");
        assertEq(wrappedToken.decimals(), 18, "wrapped decimals");
        assertEq(wrappedToken.decimalsOffset(), 12, "wrapped decimals offset");

        BaseAssetProvider provider = BaseAssetProvider(created.provider);
        assertEq(provider.baseAsset(), created.wrappedToken, "provider base asset");
        assertEq(provider.defaultAsset(), USDC, "provider default asset");
        assertEq(provider.getRate(created.wrappedToken), 1e18, "wrapper rate");
        assertEq(provider.getRate(USDC), 1e18, "default asset rate");
    }

    function test_CreateVault_Proxy_Admins_And_Roles_Set_Correctly() public view {
        IVaultView vault = IVaultView(created.vault);

        assertEq(_proxyAdminOwner(created.vault), created.timelock, "vault proxy admin owner");
        assertEq(_proxyAdminOwner(created.wrappedToken), created.timelock, "wrapper proxy admin owner");
        assertEq(_proxyAdminOwner(created.withdrawalRequest), created.timelock, "request proxy admin owner");
        assertEq(_proxyAdminOwner(created.withdrawer), created.timelock, "withdrawer proxy admin owner");
        assertEq(_proxyAdminOwner(created.bagFactory), created.timelock, "bag factory proxy admin owner");

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), created.timelock), "vault admin");
        assertTrue(vault.hasRole(vault.PROCESSOR_ROLE(), PROCESSOR), "processor");
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), PAUSER), "pauser");
        assertTrue(vault.hasRole(vault.UNPAUSER_ROLE(), UNPAUSER), "unpauser");
        assertTrue(vault.hasRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER), "fee manager");
        assertTrue(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), created.timelock), "provider manager");
        assertTrue(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), created.timelock), "buffer manager");
        assertTrue(vault.hasRole(vault.ASSET_MANAGER_ROLE(), created.timelock), "asset manager");
        assertTrue(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), created.timelock), "processor manager");
        assertTrue(vault.hasRole(vault.HOOKS_MANAGER_ROLE(), created.timelock), "hooks manager");
        assertTrue(vault.hasRole(vault.ASSET_WITHDRAWER_ROLE(), created.withdrawer), "asset withdrawer");

        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(factory)), "factory admin cleared");
        assertFalse(vault.hasRole(vault.UNPAUSER_ROLE(), address(factory)), "factory unpauser cleared");
    }

    function test_CreateVault_Withdrawal_System_Set_Correctly() public view {
        IWithdrawalRequestView request = IWithdrawalRequestView(created.withdrawalRequest);
        IWithdrawerView withdrawer = IWithdrawerView(created.withdrawer);
        IBeaconProxyFactoryView bagFactory = IBeaconProxyFactoryView(created.bagFactory);

        assertEq(request.token(), created.vault, "request token");
        assertEq(request.bagFactory(), created.bagFactory, "request bag factory");
        assertEq(request.withdrawer(), created.withdrawer, "request withdrawer");
        assertEq(request.requestPolicy(), created.requestPolicy, "request policy");
        assertEq(request.maxDataLength(), MAX_DATA_LENGTH, "max data length");
        assertTrue(request.hasRole(request.DEFAULT_ADMIN_ROLE(), created.timelock), "request admin");
        assertTrue(request.hasRole(request.RESOLVER_ROLE(), RESOLVER), "request resolver");
        assertTrue(request.hasRole(request.CONFIGURATION_MANAGER_ROLE(), created.timelock), "request config manager");
        assertTrue(request.hasRole(request.PAUSER_ROLE(), PAUSER), "request pauser");

        assertEq(withdrawer.token(), created.vault, "withdrawer token");
        assertEq(withdrawer.withdrawalRequest(), created.withdrawalRequest, "withdrawer request");

        assertEq(bagFactory.implementation(), RegistryImplementations.BAG_IMPLEMENTATION, "bag implementation");
        assertTrue(bagFactory.hasRole(bagFactory.DEFAULT_ADMIN_ROLE(), created.timelock), "bag admin");
        assertTrue(bagFactory.hasRole(bagFactory.CREATOR_ROLE(), created.withdrawalRequest), "bag creator");
        assertTrue(
            bagFactory.hasRole(bagFactory.IMPLEMENTATION_MANAGER_ROLE(), created.timelock), "bag implementation manager"
        );

        assertEq(IRequestPolicyView(created.requestPolicy).minWithdrawalAmount(), MIN_WITHDRAWAL_AMOUNT, "min request");
    }

    function test_CreateVault_Flex_Strategy_Requires_Registered_Implementations() public {
        IVaultFactory.FlexStrategyParams memory flexParams;
        flexParams.deployStrategy = true;
        flexParams.multisig = address(0x5AFE);
        flexParams.offRampAddress = address(0x0FF);
        flexParams.accountingProcessor = PROCESSOR;
        flexParams.targetApy = 0.05e18;
        flexParams.lowerBound = 0.01e18;
        flexParams.minRewardableAssets = 100e6;
        flexParams.strategyName = "Flex Strategy";
        flexParams.strategySymbol = "FLEX";
        flexParams.accountingTokenName = "Flex Accounting";
        flexParams.accountingTokenSymbol = "aFLEX";

        deal(USDC, CREATOR, BOOTSTRAP_AMOUNT);

        // This registry populates only the core keys, so the flex path must fail closed on the
        // first missing flex implementation.
        vm.startPrank(CREATOR);
        IERC20(USDC).approve(address(factory), BOOTSTRAP_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultFactory.MissingRegistryValue.selector, RegistryKeys.FLEX_STRATEGY)
        );
        factory.createVault(_vaultParams(), flexParams);
        vm.stopPrank();
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
            minWithdrawalAmount: MIN_WITHDRAWAL_AMOUNT,
            maxDataLength: MAX_DATA_LENGTH,
            bootstrapAmount: BOOTSTRAP_AMOUNT,
            bootstrapReceiver: BOOTSTRAP_RECEIVER
        });
    }

    function _emptyFlexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory flexParams) {
        flexParams.deployStrategy = false;
    }

    function _proxyAdminOwner(address proxy) internal view returns (address) {
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
        return IProxyAdminOwner(proxyAdmin).owner();
    }
}
