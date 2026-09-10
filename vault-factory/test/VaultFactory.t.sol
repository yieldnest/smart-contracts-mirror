// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IVaultFactory} from "src/interfaces/IVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MinAmountRequestPolicy} from "yieldnest-vault-withdrawals/src/policies/MinAmountRequestPolicy.sol";
import {Registry} from "src/Registry.sol";
import {RegistryKeys} from "src/lib/RegistryKeys.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {ISafeGuard} from "src/interfaces/external/ISafeGuard.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";
import {FixedRateProvider} from "src/provider/FixedRateProvider.sol";
import {FlexProvider} from "src/provider/FlexProvider.sol";
import {IVault as IVaultTypes} from "src/interfaces/external/IVault.sol";

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
    uint8 public constant VAULT_DECIMALS = 18;

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
    mapping(address => uint8) public assetDecimals;
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
        assetDecimals[asset] = IERC20Metadata(asset).decimals();
    }

    function setProvider(address provider_) external onlyRole(PROVIDER_MANAGER_ROLE) {
        provider = provider_;
    }

    address[] public ruleTargets;
    bytes4[] public ruleSigs;

    function setProcessorRule(address target, bytes4 functionSig, IVaultTypes.FunctionRule calldata rule)
        external
        onlyRole(PROCESSOR_MANAGER_ROLE)
    {
        require(rule.isActive, "active");
        ruleTargets.push(target);
        ruleSigs.push(functionSig);
    }

    function ruleCount() external view returns (uint256) {
        return ruleTargets.length;
    }

    function setBuffer(address buffer_) external onlyRole(BUFFER_MANAGER_ROLE) {
        buffer = buffer_;
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        require(provider != address(0), "provider");
        paused = false;
    }

    function deposit(uint256 amount, address receiver) public virtual returns (uint256 shares) {
        require(!paused, "paused");
        address asset = assets[defaultAssetIndex];
        shares = amount * 10 ** (VAULT_DECIMALS - assetDecimals[asset]);
        // Tolerates no-return-data tokens like USDT, as the real vault's SafeERC20 usage does.
        (bool success, bytes memory data) =
            asset.call(abi.encodeCall(IERC20.transferFrom, (msg.sender, address(this), amount)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer");
        shareBalance[receiver] += shares;
        totalSupply += shares;
    }
}

contract MockBadBootstrapVault is MockVault {
    function deposit(uint256 amount, address receiver) public override returns (uint256 shares) {
        shares = super.deposit(amount, receiver);
        return shares / 2;
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

abstract contract MockAccessControl {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    modifier onlyRole(bytes32 role) {
        require(hasRole[role][msg.sender], "role");
        _;
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        hasRole[role][account] = true;
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        require(msg.sender == callerConfirmation, "confirmation");
        hasRole[role][callerConfirmation] = false;
    }
}

contract MockFlexStrategy is MockAccessControl {
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant PROVIDER_MANAGER_ROLE = keccak256("PROVIDER_MANAGER_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    bytes32 public constant BUFFER_MANAGER_ROLE = keccak256("BUFFER_MANAGER_ROLE");
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 public constant ALLOCATOR_MANAGER_ROLE = keccak256("ALLOCATOR_MANAGER_ROLE");
    bytes32 public constant HOOKS_MANAGER_ROLE = keccak256("HOOKS_MANAGER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");

    string public name;
    string public symbol;
    uint8 public decimals;
    address public baseAsset;
    address public accountingToken;
    address public provider;
    address public hooks;
    bool public paused;
    bool public alwaysComputeTotalAssets;
    bool public hasAllocator;
    address public accountingModule;
    bool public initialized;
    mapping(address => uint256) public shareBalance;
    address[] public ruleTargets;
    bytes4[] public ruleSigs;

    function initialize(
        address admin,
        address accountingModuleManager,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address baseAsset_,
        address accountingToken_,
        bool paused_,
        address provider_,
        bool alwaysComputeTotalAssets_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
        hasRole[ACCOUNTING_MODULE_MANAGER_ROLE][accountingModuleManager] = true;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        baseAsset = baseAsset_;
        accountingToken = accountingToken_;
        paused = paused_;
        provider = provider_;
        alwaysComputeTotalAssets = alwaysComputeTotalAssets_;
    }

    function setHasAllocator(bool hasAllocators_) external onlyRole(ALLOCATOR_MANAGER_ROLE) {
        hasAllocator = hasAllocators_;
    }

    function setAccountingModule(address accountingModule_) external onlyRole(ACCOUNTING_MODULE_MANAGER_ROLE) {
        accountingModule = accountingModule_;
    }

    function setHooks(address hooks_) external onlyRole(HOOKS_MANAGER_ROLE) {
        hooks = hooks_;
    }

    function setProcessorRule(address target, bytes4 functionSig, IVaultTypes.FunctionRule calldata rule)
        external
        onlyRole(PROCESSOR_MANAGER_ROLE)
    {
        require(rule.isActive, "active");
        ruleTargets.push(target);
        ruleSigs.push(functionSig);
    }

    function ruleCount() external view returns (uint256) {
        return ruleTargets.length;
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        paused = false;
    }

    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!paused, "paused");
        if (hasAllocator) require(hasRole[ALLOCATOR_ROLE][msg.sender], "allocator");
        require(MockToken(baseAsset).transferFrom(msg.sender, address(this), amount), "transfer");
        shares = amount;
        shareBalance[receiver] += shares;
    }

    function asset() external view returns (address) {
        return baseAsset;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }
}

contract MockAccountingToken is MockAccessControl {
    bytes32 public constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");

    address public immutable TRACKED_ASSET;
    uint8 private immutable trackedDecimals;

    string public name;
    string public symbol;
    address public accountingModule;
    bool public initialized;

    constructor(address trackedAsset) {
        TRACKED_ASSET = trackedAsset;
        trackedDecimals = IERC20Metadata(trackedAsset).decimals();
    }

    function initialize(address admin, address accountingModuleManager, string memory name_, string memory symbol_)
        external
    {
        require(!initialized, "initialized");
        initialized = true;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
        hasRole[ACCOUNTING_MODULE_MANAGER_ROLE][accountingModuleManager] = true;
        name = name_;
        symbol = symbol_;
    }

    function decimals() external view returns (uint8) {
        return trackedDecimals;
    }

    function setAccountingModule(address accountingModule_) external onlyRole(ACCOUNTING_MODULE_MANAGER_ROLE) {
        accountingModule = accountingModule_;
    }
}

contract MockAccountingTokenFactory {
    function deployAccountingTokenImplementation(address trackedAsset) external returns (address) {
        return address(new MockAccountingToken(trackedAsset));
    }
}

contract MockAccountingModule is MockAccessControl {
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 public constant REWARDS_PROCESSOR_ROLE = keccak256("REWARDS_PROCESSOR_ROLE");
    bytes32 public constant LOSS_PROCESSOR_ROLE = keccak256("LOSS_PROCESSOR_ROLE");

    address public strategy;
    address public safe;
    address public accountingToken;
    uint256 public targetApy;
    uint256 public lowerBound;
    uint256 public minRewardableAssets;
    uint16 public cooldownSeconds;
    bool public initialized;

    function initialize(
        address strategy_,
        address admin,
        address safe_,
        address accountingToken_,
        uint256 targetApy_,
        uint256 lowerBound_,
        uint256 minRewardableAssets_,
        uint16 cooldownSeconds_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
        strategy = strategy_;
        safe = safe_;
        accountingToken = accountingToken_;
        targetApy = targetApy_;
        lowerBound = lowerBound_;
        minRewardableAssets = minRewardableAssets_;
        cooldownSeconds = cooldownSeconds_;
    }
}

contract MockRewardsSweeper is MockAccessControl {
    bytes32 public constant REWARDS_SWEEPER_ROLE = keccak256("REWARDS_SWEEPER_ROLE");
    bytes32 public constant SNAPSHOT_REWARDS_SWEEPER_ROLE = keccak256("SNAPSHOT_REWARDS_SWEEPER_ROLE");
    bytes32 public constant ACCOUNTING_MODULE_MANAGER_ROLE = keccak256("ACCOUNTING_MODULE_MANAGER_ROLE");

    address public accountingModule;
    bool public initialized;

    function initialize(address admin, address accountingModuleManager, address accountingModule_) external {
        require(!initialized, "initialized");
        initialized = true;
        hasRole[DEFAULT_ADMIN_ROLE][admin] = true;
        hasRole[ACCOUNTING_MODULE_MANAGER_ROLE][accountingModuleManager] = true;
        accountingModule = accountingModule_;
    }
}

contract MockAccountingModuleHook {
    address public immutable VAULT;
    address public immutable flexStrategy;

    constructor(address vault_, address flexStrategy_) {
        VAULT = vault_;
        flexStrategy = flexStrategy_;
    }
}

contract MockHooksDeployer {
    address public lastVault;
    address public lastFlexStrategy;
    address public lastHook;

    function deployAccountingModuleHook(address vault, address flexStrategy) external returns (address hook) {
        lastVault = vault;
        lastFlexStrategy = flexStrategy;
        hook = address(new MockAccountingModuleHook(vault, flexStrategy));
        lastHook = hook;
    }
}

contract MockSafeGuard {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 public constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");

    string public name;
    address public admin;
    bool public initialized;
    address[] public ruleTargets;
    bytes4[] public ruleSigs;
    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(address => mapping(bytes4 => ISafeGuard.FunctionRule)) private rules;

    function initialize(string calldata name_, address admin_) external {
        require(!initialized, "initialized");
        initialized = true;
        name = name_;
        admin = admin_;
        hasRole[DEFAULT_ADMIN_ROLE][admin_] = true;
        hasRole[PROCESSOR_MANAGER_ROLE][admin_] = true;
        hasRole[GUARD_ADMIN_ROLE][admin_] = true;
    }

    function grantRole(bytes32 role, address account) external {
        require(hasRole[DEFAULT_ADMIN_ROLE][msg.sender], "admin");
        hasRole[role][account] = true;
        if (role == DEFAULT_ADMIN_ROLE) admin = account;
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        require(msg.sender == callerConfirmation, "confirmation");
        hasRole[role][callerConfirmation] = false;
    }

    function setProcessorRules(
        address[] calldata target,
        bytes4[] calldata functionSig,
        ISafeGuard.FunctionRule[] calldata rule
    ) external {
        require(hasRole[PROCESSOR_MANAGER_ROLE][msg.sender], "role");
        require(target.length == functionSig.length && target.length == rule.length, "length");
        for (uint256 i = 0; i < target.length; ++i) {
            rules[target[i]][functionSig[i]] = rule[i];
            ruleTargets.push(target[i]);
            ruleSigs.push(functionSig[i]);
        }
    }

    function getProcessorRule(address contractAddress, bytes4 funcSig)
        external
        view
        returns (ISafeGuard.FunctionRule memory)
    {
        return rules[contractAddress][funcSig];
    }
}

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
    MockFlexStrategy private flexStrategyLogic;
    MockAccountingModule private accountingModuleLogic;
    MockAccountingTokenFactory private accountingTokenFactory;
    MockRewardsSweeper private rewardsSweeperLogic;
    MockHooksDeployer private hooksDeployer;
    MockSafeGuard private safeGuardLogic;

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

        flexStrategyLogic = new MockFlexStrategy();
        accountingModuleLogic = new MockAccountingModule();
        accountingTokenFactory = new MockAccountingTokenFactory();
        rewardsSweeperLogic = new MockRewardsSweeper();

        registry.setValue(RegistryKeys.FLEX_STRATEGY, address(flexStrategyLogic));
        registry.setValue(RegistryKeys.ACCOUNTING_MODULE, address(accountingModuleLogic));
        registry.setValue(RegistryKeys.ACCOUNTING_TOKEN_FACTORY, address(accountingTokenFactory));
        registry.setValue(RegistryKeys.REWARDS_SWEEPER, address(rewardsSweeperLogic));
        hooksDeployer = new MockHooksDeployer();
        registry.setValue(RegistryKeys.HOOKS_DEPLOYER, address(hooksDeployer));
        safeGuardLogic = new MockSafeGuard();
        registry.setValue(RegistryKeys.SAFE_GUARD, address(safeGuardLogic));

        asset.mint(creator, 1 ether);
    }

    function testCreateVaultConfiguresMainVaultAndBootstraps() public {
        assertEq(factory.VERSION(), "0.1.0");

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        IVaultFactory.CreatedVault memory created = factory.createVault(_vaultParams(1 ether), _emptyFlexParams());
        vm.stopPrank();

        assertEq(created.safeGuard, address(0));
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
        assertEq(providerContract.defaultAsset(), address(asset));
        assertEq(providerContract.rate(), 1e18);
        assertEq(providerContract.getRate(address(asset)), 1e18);
        assertEq(vault.shareBalance(bootstrapReceiver), 1 ether);
        assertEq(asset.balanceOf(created.vault), 1 ether);

        // With 18 decimals there is no wrapper: the base asset is itself the ERC4626 default
        // asset and must accept deposits.
        assertEq(vault.assets(0), address(asset));
        assertTrue(vault.activeAsset(address(asset)));

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
        // The wrapper is an accounting-only denominator and must not be depositable.
        assertFalse(vault.activeAsset(created.wrappedToken));
        assertEq(vault.assets(1), address(usdc));
        assertTrue(vault.activeAsset(address(usdc)));
        assertEq(vault.defaultAssetIndex(), 1);
        assertEq(vault.shareBalance(bootstrapReceiver), 1 ether);
        assertEq(usdc.balanceOf(created.vault), 1e6);

        assertEq(BaseAssetProvider(created.provider).baseAsset(), created.wrappedToken);
        assertEq(BaseAssetProvider(created.provider).defaultAsset(), address(usdc));
        assertEq(BaseAssetProvider(created.provider).getRate(created.wrappedToken), 1e18);
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
        assertEq(vault.shareBalance(bootstrapReceiver), 1 ether);
        assertEq(usdt.balanceOf(created.vault), 1e6);
        assertEq(usdt.allowance(address(factory), created.vault), 0);
    }

    function testCreateVaultRevertsWhenBootstrapSharesMismatch() public {
        MockBadBootstrapVault badVaultLogic = new MockBadBootstrapVault();
        registry.setValue(RegistryKeys.VAULT, address(badVaultLogic));

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.BootstrapSharesMismatch.selector, 0.5 ether, 1 ether));
        factory.createVault(_vaultParams(1 ether), _emptyFlexParams());
        vm.stopPrank();
    }

    function testCreateVaultDeploysFlexStrategy() public {
        MockToken usdc = new MockToken(6);
        // Vault bootstrap plus strategy bootstrap.
        usdc.mint(creator, 2e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6);
        params.baseAsset = address(usdc);

        vm.startPrank(creator);
        usdc.approve(address(factory), 2e6);
        IVaultFactory.CreatedVault memory created = factory.createVault(params, _flexParams());
        vm.stopPrank();

        MockVault vault = MockVault(created.vault);
        MockFlexStrategy strategy = MockFlexStrategy(created.flexStrategy);
        MockAccountingToken accountingToken = MockAccountingToken(created.accountingToken);
        MockAccountingModule accountingModule = MockAccountingModule(created.accountingModule);
        MockRewardsSweeper rewardsSweeper = MockRewardsSweeper(created.rewardsSweeper);

        _assertSafeGuard(created, address(usdc), address(0x0FF));

        // Strategy initialization and wiring.
        assertTrue(strategy.initialized());
        assertEq(strategy.name(), "Flex Strategy");
        assertEq(strategy.symbol(), "FLEX");
        assertEq(strategy.decimals(), 6);
        assertEq(strategy.baseAsset(), address(usdc));
        assertEq(strategy.accountingToken(), created.accountingToken);
        assertEq(strategy.accountingModule(), created.accountingModule);
        assertFalse(strategy.paused());
        assertTrue(strategy.hasAllocator());
        assertEq(strategy.hooks(), created.accountingModuleHook);
        assertEq(hooksDeployer.lastVault(), created.flexStrategy);
        assertEq(hooksDeployer.lastFlexStrategy(), created.flexStrategy);
        assertEq(hooksDeployer.lastHook(), created.accountingModuleHook);
        assertEq(MockAccountingModuleHook(created.accountingModuleHook).VAULT(), created.flexStrategy);
        assertEq(MockAccountingModuleHook(created.accountingModuleHook).flexStrategy(), created.flexStrategy);

        // The vault provider prices the wrapper, the default asset, and the strategy.
        FlexProvider provider = FlexProvider(created.provider);
        assertEq(vault.provider(), created.provider);
        assertEq(provider.baseAsset(), created.wrappedToken);
        assertEq(provider.defaultAsset(), address(usdc));
        assertEq(provider.strategy(), created.flexStrategy);
        assertEq(provider.getRate(created.wrappedToken), 1e18);
        assertEq(provider.getRate(address(usdc)), 1e18);
        assertEq(provider.getRate(created.flexStrategy), 1e18);

        // The strategy's own provider prices the base asset and accounting token at par.
        FixedRateProvider strategyProvider = FixedRateProvider(strategy.provider());
        assertEq(strategyProvider.ASSET(), address(usdc));
        assertEq(strategyProvider.ACCOUNTING_TOKEN(), created.accountingToken);
        assertEq(strategyProvider.getRate(address(usdc)), 1e6);

        // Strategy shares are the vault's third asset.
        assertEq(vault.assets(0), created.wrappedToken);
        assertEq(vault.assets(1), address(usdc));
        assertEq(vault.assets(2), created.flexStrategy);
        // Only the ERC4626 default asset accepts deposits; the wrapper and the strategy are
        // accounting-only and added inactive.
        assertFalse(vault.activeAsset(created.wrappedToken));
        assertTrue(vault.activeAsset(address(usdc)));
        assertFalse(vault.activeAsset(created.flexStrategy));

        // Vault rules: approve on the default asset plus deposit/mint/withdraw/redeem on the strategy.
        assertEq(vault.ruleCount(), 5);
        assertEq(vault.ruleTargets(0), address(usdc));
        assertEq(vault.ruleSigs(0), bytes4(keccak256("approve(address,uint256)")));
        assertEq(vault.ruleTargets(1), created.flexStrategy);
        assertEq(vault.ruleSigs(1), bytes4(keccak256("deposit(uint256,address)")));
        assertEq(vault.ruleSigs(2), bytes4(keccak256("mint(uint256,address)")));
        assertEq(vault.ruleSigs(3), bytes4(keccak256("withdraw(uint256,address,address)")));
        assertEq(vault.ruleSigs(4), bytes4(keccak256("redeem(uint256,address,address)")));

        // Strategy rules: the strategy processor may only use the accounting module.
        assertEq(strategy.ruleCount(), 2);
        assertEq(strategy.ruleTargets(0), created.accountingModule);
        assertEq(strategy.ruleSigs(0), bytes4(keccak256("deposit(uint256)")));
        assertEq(strategy.ruleTargets(1), created.accountingModule);
        assertEq(strategy.ruleSigs(1), bytes4(keccak256("withdraw(uint256,address)")));

        // Strategy roles: timelock critical, actors operational, vault allocator, factory clean.
        assertTrue(strategy.hasRole(strategy.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.PROCESSOR_ROLE(), processor));
        assertTrue(strategy.hasRole(strategy.PAUSER_ROLE(), pauser));
        assertTrue(strategy.hasRole(strategy.UNPAUSER_ROLE(), unpauser));
        assertTrue(strategy.hasRole(strategy.PROVIDER_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.ASSET_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.BUFFER_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.PROCESSOR_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.ALLOCATOR_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.HOOKS_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.ACCOUNTING_MODULE_MANAGER_ROLE(), created.timelock));
        assertTrue(strategy.hasRole(strategy.ALLOCATOR_ROLE(), created.vault));
        assertTrue(strategy.hasRole(strategy.PROCESSOR_ROLE(), created.accountingModuleHook));
        assertFalse(strategy.hasRole(strategy.ALLOCATOR_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.PROCESSOR_MANAGER_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.ALLOCATOR_MANAGER_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.HOOKS_MANAGER_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.UNPAUSER_ROLE(), address(factory)));
        assertFalse(strategy.hasRole(strategy.ACCOUNTING_MODULE_MANAGER_ROLE(), address(factory)));

        // Accounting token wiring.
        assertEq(accountingToken.TRACKED_ASSET(), address(usdc));
        assertEq(accountingToken.name(), "Flex Accounting");
        assertEq(accountingToken.symbol(), "aFLEX");
        assertEq(accountingToken.accountingModule(), created.accountingModule);
        assertTrue(accountingToken.hasRole(accountingToken.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(accountingToken.hasRole(accountingToken.ACCOUNTING_MODULE_MANAGER_ROLE(), created.timelock));
        assertFalse(accountingToken.hasRole(accountingToken.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(accountingToken.hasRole(accountingToken.ACCOUNTING_MODULE_MANAGER_ROLE(), address(factory)));

        // Accounting module wiring.
        assertEq(accountingModule.strategy(), created.flexStrategy);
        assertEq(accountingModule.safe(), address(0x5AFE));
        assertEq(accountingModule.accountingToken(), created.accountingToken);
        assertEq(accountingModule.targetApy(), 0.05e18);
        assertEq(accountingModule.lowerBound(), 0.01e18);
        assertEq(accountingModule.minRewardableAssets(), 100e6);
        assertEq(accountingModule.cooldownSeconds(), 1 hours);
        assertTrue(accountingModule.hasRole(accountingModule.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(accountingModule.hasRole(accountingModule.SAFE_MANAGER_ROLE(), created.timelock));
        assertTrue(accountingModule.hasRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(0xACC0)));
        assertTrue(accountingModule.hasRole(accountingModule.REWARDS_PROCESSOR_ROLE(), created.rewardsSweeper));
        assertTrue(accountingModule.hasRole(accountingModule.LOSS_PROCESSOR_ROLE(), address(0x5AFE)));
        assertFalse(accountingModule.hasRole(accountingModule.DEFAULT_ADMIN_ROLE(), address(factory)));

        // Rewards sweeper wiring.
        assertEq(rewardsSweeper.accountingModule(), created.accountingModule);
        assertTrue(rewardsSweeper.hasRole(rewardsSweeper.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(rewardsSweeper.hasRole(rewardsSweeper.ACCOUNTING_MODULE_MANAGER_ROLE(), created.timelock));
        assertTrue(rewardsSweeper.hasRole(rewardsSweeper.REWARDS_SWEEPER_ROLE(), processor));
        assertTrue(rewardsSweeper.hasRole(rewardsSweeper.SNAPSHOT_REWARDS_SWEEPER_ROLE(), processor));
        assertFalse(rewardsSweeper.hasRole(rewardsSweeper.DEFAULT_ADMIN_ROLE(), address(factory)));

        // Bootstraps: vault holds one unit of USDC, strategy holds the other with shares to the vault.
        assertEq(vault.shareBalance(bootstrapReceiver), 1e18);
        assertEq(usdc.balanceOf(created.vault), 1e6);
        assertEq(usdc.balanceOf(created.flexStrategy), 1e6);
        assertEq(strategy.shareBalance(created.vault), 1e6);

        // All strategy-system proxies share the vault timelock as proxy admin owner.
        address strategyProxyAdmin = address(uint160(uint256(vm.load(created.flexStrategy, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(strategyProxyAdmin).owner(), created.timelock);
        address tokenProxyAdmin = address(uint160(uint256(vm.load(created.accountingToken, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(tokenProxyAdmin).owner(), created.timelock);
        address moduleProxyAdmin = address(uint160(uint256(vm.load(created.accountingModule, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(moduleProxyAdmin).owner(), created.timelock);
        address sweeperProxyAdmin = address(uint160(uint256(vm.load(created.rewardsSweeper, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(sweeperProxyAdmin).owner(), created.timelock);
    }

    function _assertSafeGuard(IVaultFactory.CreatedVault memory created, address baseAsset, address offRampAddress)
        internal
        view
    {
        MockSafeGuard safeGuard = MockSafeGuard(created.safeGuard);

        assertTrue(safeGuard.initialized());
        assertEq(safeGuard.name(), "Flex Strategy Safeguard");
        assertEq(safeGuard.admin(), created.timelock);
        assertTrue(safeGuard.hasRole(safeGuard.DEFAULT_ADMIN_ROLE(), created.timelock));
        assertTrue(safeGuard.hasRole(safeGuard.PROCESSOR_MANAGER_ROLE(), created.timelock));
        assertTrue(safeGuard.hasRole(safeGuard.GUARD_ADMIN_ROLE(), created.timelock));
        assertFalse(safeGuard.hasRole(safeGuard.DEFAULT_ADMIN_ROLE(), address(factory)));
        assertFalse(safeGuard.hasRole(safeGuard.PROCESSOR_MANAGER_ROLE(), address(factory)));
        assertFalse(safeGuard.hasRole(safeGuard.GUARD_ADMIN_ROLE(), address(factory)));
        assertEq(safeGuard.ruleTargets(0), baseAsset);
        assertEq(safeGuard.ruleSigs(0), IERC20.transfer.selector);

        ISafeGuard.FunctionRule memory transferRule =
            ISafeGuard(created.safeGuard).getProcessorRule(baseAsset, IERC20.transfer.selector);
        assertTrue(transferRule.isActive);
        assertEq(transferRule.paramRules.length, 2);
        assertEq(uint8(transferRule.paramRules[0].paramType), uint8(ISafeGuard.ParamType.ADDRESS));
        assertEq(transferRule.paramRules[0].allowList.length, 1);
        assertEq(transferRule.paramRules[0].allowList[0], offRampAddress);
        assertEq(uint8(transferRule.paramRules[1].paramType), uint8(ISafeGuard.ParamType.UINT256));
        assertEq(transferRule.paramRules[1].allowList.length, 0);
        assertEq(transferRule.validator, address(0));

        address safeGuardProxyAdmin = address(uint160(uint256(vm.load(created.safeGuard, ERC1967_ADMIN_SLOT))));
        assertEq(IProxyAdminOwner(safeGuardProxyAdmin).owner(), created.timelock);
    }

    function testCreateVaultDeploysFlexStrategyWithoutRewardsSweeper() public {
        MockToken usdc = new MockToken(6);
        usdc.mint(creator, 2e6);

        IVaultFactory.VaultParams memory params = _vaultParams(1e6);
        params.baseAsset = address(usdc);

        IVaultFactory.FlexStrategyParams memory flexParams = _flexParams();
        flexParams.deployRewardsSweeper = false;

        vm.startPrank(creator);
        usdc.approve(address(factory), 2e6);
        IVaultFactory.CreatedVault memory created = factory.createVault(params, flexParams);
        vm.stopPrank();

        assertEq(created.rewardsSweeper, address(0));
        assertTrue(created.flexStrategy != address(0));

        MockAccountingModule accountingModule = MockAccountingModule(created.accountingModule);
        assertTrue(accountingModule.hasRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(0xACC0)));
        assertFalse(accountingModule.hasRole(accountingModule.REWARDS_PROCESSOR_ROLE(), address(0)));
    }

    function testCreateVaultFlexStrategyRequiresMultisigAndProcessor() public {
        IVaultFactory.FlexStrategyParams memory flexParams = _flexParams();
        flexParams.multisig = address(0);

        vm.startPrank(creator);
        asset.approve(address(factory), 1 ether);
        vm.expectRevert(IVaultFactory.ZeroAddress.selector);
        factory.createVault(_vaultParams(1 ether), flexParams);
        vm.stopPrank();
    }

    function testCreateVaultFlexStrategyRequiresOffRampAddress() public {
        IVaultFactory.FlexStrategyParams memory flexParams = _flexParams();
        flexParams.offRampAddress = address(0);

        vm.startPrank(creator);
        asset.approve(address(factory), 2 ether);
        vm.expectRevert(IVaultFactory.ZeroAddress.selector);
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

    function testAdvanceNonceDeploysMarkerAndAdvancesFactoryNonce() public {
        uint64 nonceBefore = vm.getNonce(address(factory));

        address marker = factory.advanceNonce();

        assertEq(vm.getNonce(address(factory)), nonceBefore + 1);
        assertGt(marker.code.length, 0);
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

    function _emptyFlexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory flexParams) {
        flexParams.deployStrategy = false;
    }

    function _flexParams() internal pure returns (IVaultFactory.FlexStrategyParams memory) {
        return IVaultFactory.FlexStrategyParams({
            deployStrategy: true,
            deployRewardsSweeper: true,
            multisig: address(0x5AFE),
            offRampAddress: address(0x0FF),
            accountingProcessor: address(0xACC0),
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
