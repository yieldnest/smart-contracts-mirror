// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinAmountRequestPolicy} from "yieldnest-vault-withdrawals/src/policies/MinAmountRequestPolicy.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";

interface IProxyAdminOwner {
    function owner() external view returns (address);
}

contract RegistryProxy {
    address public immutable logic;

    constructor(address logic_, bytes memory initData) {
        logic = logic_;

        if (initData.length != 0) {
            (bool success, bytes memory returnData) = logic_.delegatecall(initData);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    receive() external payable {}

    fallback() external payable {
        address logic_ = logic;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), logic_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract MockToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 decimals_) {
        name = "Asset";
        symbol = "AST";
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");

        allowance[from][msg.sender] = currentAllowance - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// Mimics mainnet USDT: no return values, and non-zero approvals require a zero allowance first.
contract MockUSDTToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 decimals_) {
        name = "Tether USD";
        symbol = "USDT";
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        require(amount == 0 || allowance[msg.sender][spender] == 0, "reset allowance");
        allowance[msg.sender][spender] = amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");

        allowance[from][msg.sender] = currentAllowance - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract MockVault {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 public constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant ASSET_WITHDRAWER_ROLE = keccak256("ASSET_WITHDRAWER_ROLE");

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(address => bool) public activeAsset;
    address[] public assets;
    mapping(address => uint256) public shareBalance;

    address public provider;
    address public buffer;
    bool public paused;
    bool public initialized;
    string public tokenName;
    string public tokenSymbol;
    uint8 public tokenDecimals;
    bool public countNativeAsset;
    bool public alwaysComputeTotalAssets;
    uint256 public defaultAssetIndex;
    uint256 public totalSupply;

    modifier onlyRole(bytes32 role) {
        require(hasRole[role][msg.sender], "role");
        _;
    }

    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        paused = true;
        tokenName = name;
        tokenSymbol = symbol;
        tokenDecimals = decimals_;
        countNativeAsset = countNativeAsset_;
        alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
        defaultAssetIndex = defaultAssetIndex_;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        hasRole[role][account] = true;
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        require(msg.sender == callerConfirmation, "confirmation");
        hasRole[role][callerConfirmation] = false;
    }

    function addAsset(address asset, bool active) external onlyRole(ASSET_MANAGER_ROLE) {
        assets.push(asset);
        activeAsset[asset] = active;
    }

    function setProvider(address provider_) external onlyRole(PROVIDER_MANAGER_ROLE) {
        provider = provider_;
    }

    function setBuffer(address buffer_) external onlyRole(BUFFER_MANAGER_ROLE) {
        buffer = buffer_;
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        require(provider != address(0), "provider");
        paused = false;
    }

    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!paused, "paused");
        address asset = assets[defaultAssetIndex];
        // Tolerates no-return-data tokens like USDT, as the real vault's SafeERC20 usage does.
        (bool success, bytes memory data) =
            asset.call(abi.encodeCall(IERC20.transferFrom, (msg.sender, address(this), amount)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer");
        shareBalance[receiver] += amount;
        totalSupply += amount;
        return amount;
    }
}

contract MockWrappedToken {
    IERC20 public underlyingToken;
    string public name;
    string public symbol;
    uint8 public decimals;
    uint8 public decimalsOffset;
    bool public initialized;

    function initialize(
        IERC20 underlyingToken_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint8 decimalsOffset_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        underlyingToken = underlyingToken_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        decimalsOffset = decimalsOffset_;
    }

    function asset() external view returns (address) {
        return address(underlyingToken);
    }
}

contract MockWithdrawalRequest {
    address public token;
    address public defaultAdmin;
    address public resolver;
    address public configurationManager;
    address public pauser;
    address public bagFactory;
    address public withdrawer;
    address public requestPolicy;
    uint256 public maxDataLength;
    bool public initialized;

    function initialize(
        address token_,
        address defaultAdmin_,
        address resolver_,
        address configurationManager_,
        address pauser_,
        address bagFactory_,
        address withdrawer_,
        address requestPolicy_,
        uint256 maxDataLength_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        token = token_;
        defaultAdmin = defaultAdmin_;
        resolver = resolver_;
        configurationManager = configurationManager_;
        pauser = pauser_;
        bagFactory = bagFactory_;
        withdrawer = withdrawer_;
        requestPolicy = requestPolicy_;
        maxDataLength = maxDataLength_;
    }
}

contract MockWithdrawer {
    address public token;
    address public withdrawalRequest;
    bool public initialized;

    function initialize(address token_, address withdrawalRequest_) external {
        require(!initialized, "initialized");
        initialized = true;
        token = token_;
        withdrawalRequest = withdrawalRequest_;
    }
}

contract MockBagFactory {
    address public implementation;
    address public defaultAdmin;
    address public creator;
    address public implementationManager;
    bool public initialized;

    function initialize(
        address implementation_,
        address defaultAdmin_,
        address creator_,
        address implementationManager_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        implementation = implementation_;
        defaultAdmin = defaultAdmin_;
        creator = creator_;
        implementationManager = implementationManager_;
    }
}

contract MockBag {}

contract VaultFactoryTest is Test {
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    address private admin = address(0xA11CE);
    address private processor = address(0xBEEF);
    address private pauser = address(0xCAFE);
    address private unpauser = address(0xD00D);
    address private feeManager = address(0xFEE);
    address private resolver = address(0x2E50);
    address private bootstrapReceiver = address(0xB007);
    address private creator = address(0xC0DEC);

    IRegistry private registry;
    VaultFactory private factory;
    MockToken private asset;
    MockVault private vaultLogic;
    MockWrappedToken private wrappedTokenLogic;
    MockWithdrawalRequest private withdrawalRequestLogic;
    MockWithdrawer private withdrawerLogic;
    MockBagFactory private bagFactoryLogic;
    MockBag private bagLogic;

    function setUp() public {
        Registry registryLogic = new Registry();
        RegistryProxy registryProxy =
            new RegistryProxy(address(registryLogic), abi.encodeCall(IRegistry.initialize, (address(this))));
        registry = IRegistry(address(registryProxy));

        factory = new VaultFactory(registry);
        asset = new MockToken(18);
        vaultLogic = new MockVault();
        wrappedTokenLogic = new MockWrappedToken();

        withdrawalRequestLogic = new MockWithdrawalRequest();
        withdrawerLogic = new MockWithdrawer();
        bagFactoryLogic = new MockBagFactory();
        bagLogic = new MockBag();

        registry.setValue(RegistryKeys.VAULT, address(vaultLogic));
        registry.setValue(RegistryKeys.WRAPPED_TOKEN, address(wrappedTokenLogic));
        registry.setValue(RegistryKeys.WITHDRAWAL_REQUEST, address(withdrawalRequestLogic));
        registry.setValue(RegistryKeys.WITHDRAWER, address(withdrawerLogic));
        registry.setValue(RegistryKeys.BAG_FACTORY, address(bagFactoryLogic));
        registry.setValue(RegistryKeys.BAG, address(bagLogic));

        asset.mint(creator, 1 ether);
    }

    function testCreateVaultConfiguresMainVaultAndBootstraps() public {
        assertEq(factory.VERSION(), "0.1.0");

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        IVaultFactory.CreatedVault memory created = factory.createVault(_vaultParams(1 ether), _emptyFlexParams());
        vm.stopPrank();

        assertEq(created.wrappedToken, address(0));
        MockVault vault = MockVault(created.vault);

        assertEq(vault.tokenName(), "RWA Vault");
        assertEq(vault.tokenSymbol(), "ynRWA");
        assertEq(vault.tokenDecimals(), 18);
        assertFalse(vault.countNativeAsset());
        assertTrue(vault.alwaysComputeTotalAssets());
        assertFalse(vault.paused());
        assertEq(vault.provider(), created.provider);
        assertEq(vault.buffer(), address(0));

        BaseAssetProvider providerContract = BaseAssetProvider(created.provider);
        assertEq(providerContract.baseAsset(), address(asset));
        assertEq(providerContract.rate(), 1e18);
        assertEq(providerContract.getRate(address(asset)), 1e18);
        assertEq(vault.shareBalance(bootstrapReceiver), 1 ether);
        assertEq(asset.balanceOf(created.vault), 1 ether);

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.PROCESSOR_ROLE(), processor));
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser));
        assertTrue(vault.hasRole(vault.UNPAUSER_ROLE(), unpauser));
        assertTrue(vault.hasRole(vault.FEE_MANAGER_ROLE(), feeManager));
        assertTrue(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.ASSET_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), created.timelock));
        assertTrue(vault.hasRole(vault.HOOKS_MANAGER_ROLE(), created.timelock));

        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.ASSET_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.HOOKS_MANAGER_ROLE(), address(factory)));
        assertFalse(vault.hasRole(vault.UNPAUSER_ROLE(), address(factory)));

        address proxyAdmin = address(uint160(uint256(vm.load(created.vault, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(proxyAdmin).owner(), created.timelock);

        _assertWithdrawalSystem(created);
    }

    function _assertWithdrawalSystem(IVaultFactory.CreatedVault memory created) internal view {
        MockVault vault = MockVault(created.vault);

        MockWithdrawalRequest withdrawalRequest = MockWithdrawalRequest(created.withdrawalRequest);
        assertTrue(withdrawalRequest.initialized());
        assertEq(withdrawalRequest.token(), created.vault);
        assertEq(withdrawalRequest.defaultAdmin(), created.timelock);
        assertEq(withdrawalRequest.resolver(), resolver);
        assertEq(withdrawalRequest.configurationManager(), created.timelock);
        assertEq(withdrawalRequest.pauser(), pauser);
        assertEq(withdrawalRequest.bagFactory(), created.bagFactory);
        assertEq(withdrawalRequest.withdrawer(), created.withdrawer);
        assertEq(withdrawalRequest.requestPolicy(), created.requestPolicy);
        assertEq(withdrawalRequest.maxDataLength(), 256);

        MockWithdrawer withdrawer = MockWithdrawer(created.withdrawer);
        assertEq(withdrawer.token(), created.vault);
        assertEq(withdrawer.withdrawalRequest(), created.withdrawalRequest);
        assertTrue(vault.hasRole(vault.ASSET_WITHDRAWER_ROLE(), created.withdrawer));

        MockBagFactory bagFactory = MockBagFactory(created.bagFactory);
        assertEq(bagFactory.implementation(), address(bagLogic));
        assertEq(bagFactory.defaultAdmin(), created.timelock);
        assertEq(bagFactory.creator(), created.withdrawalRequest);
        assertEq(bagFactory.implementationManager(), created.timelock);

        assertEq(MinAmountRequestPolicy(created.requestPolicy).minWithdrawalAmount(), 0.01 ether);

        address requestProxyAdmin = address(uint160(uint256(vm.load(created.withdrawalRequest, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(requestProxyAdmin).owner(), created.timelock);
        address withdrawerProxyAdmin = address(uint160(uint256(vm.load(created.withdrawer, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(withdrawerProxyAdmin).owner(), created.timelock);
        address bagFactoryProxyAdmin = address(uint160(uint256(vm.load(created.bagFactory, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(bagFactoryProxyAdmin).owner(), created.timelock);
    }

    function testCreateVaultWrapsNon18DecimalBaseAsset() public {
        MockToken usdc = new MockToken(6);
        usdc.mint(creator, 1e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6);
        params.baseAsset = address(usdc);

        vm.startPrank(creator);
        usdc.approve(address(factory), 1e6);
        IVaultFactory.CreatedVault memory created = factory.createVault(params, _emptyFlexParams());
        vm.stopPrank();

        assertTrue(created.wrappedToken != address(0));

        MockWrappedToken wrappedToken = MockWrappedToken(created.wrappedToken);
        assertEq(wrappedToken.asset(), address(usdc));
        assertEq(wrappedToken.name(), "Wrapped Asset");
        assertEq(wrappedToken.symbol(), "WAST");
        assertEq(wrappedToken.decimals(), 18);
        assertEq(wrappedToken.decimalsOffset(), 12);

        MockVault vault = MockVault(created.vault);
        assertEq(vault.assets(0), created.wrappedToken);
        assertTrue(vault.activeAsset(created.wrappedToken));
        assertEq(vault.assets(1), address(usdc));
        assertTrue(vault.activeAsset(address(usdc)));
        assertEq(vault.defaultAssetIndex(), 1);
        assertEq(vault.shareBalance(bootstrapReceiver), 1e6);
        assertEq(usdc.balanceOf(created.vault), 1e6);

        // The provider prices the default asset, not the zero-balance wrapper.
        assertEq(BaseAssetProvider(created.provider).baseAsset(), address(usdc));
        assertEq(BaseAssetProvider(created.provider).getRate(address(usdc)), 1e18);

        address wrapperProxyAdmin = address(uint160(uint256(vm.load(created.wrappedToken, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(wrapperProxyAdmin).owner(), created.timelock);
    }

    function testCreateVaultBootstrapsWithNoReturnDataToken() public {
        MockUSDTToken usdt = new MockUSDTToken(6);
        usdt.mint(creator, 1e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6);
        params.baseAsset = address(usdt);

        vm.startPrank(creator);
        usdt.approve(address(factory), 1e6);
        IVaultFactory.CreatedVault memory created = factory.createVault(params, _emptyFlexParams());
        vm.stopPrank();

        MockVault vault = MockVault(created.vault);
        assertEq(vault.shareBalance(bootstrapReceiver), 1e6);
        assertEq(usdt.balanceOf(created.vault), 1e6);
        assertEq(usdt.allowance(address(factory), created.vault), 0);
    }

    function testCreateVaultRevertsWhenFlexStrategyRequested() public {
        bytes memory deployData = abi.encode("flex config");
        IVaultFactory.FlexStrategyParams memory flexParams = IVaultFactory.FlexStrategyParams({
            deployStrategy: true, multisig: address(0x5AFE), offRampAddress: address(0x0FF), deployData: deployData
        });

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(IVaultFactory.FunctionalityUnavailable.selector);
        factory.createVault(_vaultParams(1 ether), flexParams);
        vm.stopPrank();
    }

    function testCreateVaultRevertsForMissingRegistryValue() public {
        Registry emptyRegistryLogic = new Registry();
        RegistryProxy emptyRegistryProxy =
            new RegistryProxy(address(emptyRegistryLogic), abi.encodeCall(IRegistry.initialize, (address(this))));
        VaultFactory emptyRegistryFactory = new VaultFactory(IRegistry(address(emptyRegistryProxy)));

        vm.startPrank(creator);
        asset.approve(address(emptyRegistryFactory), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.MissingRegistryValue.selector, RegistryKeys.VAULT));
        emptyRegistryFactory.createVault(_vaultParams(1 ether), _emptyFlexParams());
        vm.stopPrank();
    }

    function testDeployWithdrawalSystemStandalone() public {
        address standaloneVault = address(0x5AB1);
        address standaloneTimelock = address(0x71E1);

        IVaultFactory.WithdrawalSystem memory ws =
            factory.deployWithdrawalSystem(standaloneVault, standaloneTimelock, resolver, pauser, 1e17, 128);

        MockWithdrawalRequest withdrawalRequest = MockWithdrawalRequest(ws.withdrawalRequest);
        assertEq(withdrawalRequest.token(), standaloneVault);
        assertEq(withdrawalRequest.defaultAdmin(), standaloneTimelock);
        assertEq(withdrawalRequest.resolver(), resolver);
        assertEq(withdrawalRequest.configurationManager(), standaloneTimelock);
        assertEq(withdrawalRequest.pauser(), pauser);
        assertEq(withdrawalRequest.bagFactory(), ws.bagFactory);
        assertEq(withdrawalRequest.withdrawer(), ws.withdrawer);
        assertEq(withdrawalRequest.requestPolicy(), ws.requestPolicy);
        assertEq(withdrawalRequest.maxDataLength(), 128);

        assertEq(MockWithdrawer(ws.withdrawer).token(), standaloneVault);
        assertEq(MockWithdrawer(ws.withdrawer).withdrawalRequest(), ws.withdrawalRequest);
        assertEq(MockBagFactory(ws.bagFactory).creator(), ws.withdrawalRequest);
        assertEq(MinAmountRequestPolicy(ws.requestPolicy).minWithdrawalAmount(), 1e17);

        address requestProxyAdmin = address(uint160(uint256(vm.load(ws.withdrawalRequest, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(requestProxyAdmin).owner(), standaloneTimelock);
    }

    function testCreateVaultRevertsWhenBootstrapBelowOneUnit() public {
        MockToken usdc = new MockToken(6);
        usdc.mint(creator, 1e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6 - 1);
        params.baseAsset = address(usdc);

        vm.startPrank(creator);
        usdc.approve(address(factory), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.BootstrapAmountTooLow.selector, 1e6 - 1, 1e6));
        factory.createVault(params, _emptyFlexParams());
        vm.stopPrank();
    }

    function testCreateVaultRevertsWhenDefaultAssetDecimalsTooHigh() public {
        MockToken baseAsset = new MockToken(19);

        IVaultFactory.VaultParams memory params = _vaultParams(1 ether);
        params.baseAsset = address(baseAsset);

        vm.startPrank(creator);
        baseAsset.mint(creator, 10 ether);
        baseAsset.approve(address(factory), 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.AssetDecimalsTooHigh.selector, 19));
        factory.createVault(params, _emptyFlexParams());
        vm.stopPrank();
    }

    function _vaultParams(uint256 bootstrapAmount) internal view returns (IVaultFactory.VaultParams memory) {
        return IVaultFactory.VaultParams({
            admin: admin,
            processor: processor,
            pauser: pauser,
            unpauser: unpauser,
            feeManager: feeManager,
            resolver: resolver,
            baseAsset: address(asset),
            tokenName: "RWA Vault",
            tokenSymbol: "ynRWA",
            countNativeAsset: false,
            alwaysComputeTotalAssets: true,
            timelockDuration: 1 days,
            minWithdrawalAmount: 0.01 ether,
            maxDataLength: 256,
            bootstrapAmount: bootstrapAmount,
            bootstrapReceiver: bootstrapReceiver
        });
    }

    function _emptyFlexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: false, multisig: address(0), offRampAddress: address(0), deployData: ""
        });
    }
}
