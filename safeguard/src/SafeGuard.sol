// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseTransactionGuard, ITransactionGuard} from "lib/safe-smart-account/contracts/base/GuardManager.sol";
import {BaseModuleGuard, IModuleGuard} from "lib/safe-smart-account/contracts/base/ModuleManager.sol";
import {IERC165} from "lib/safe-smart-account/contracts/interfaces/IERC165.sol";
import {Enum} from "lib/safe-smart-account/contracts/libraries/Enum.sol";
import {Guard} from "lib/yieldnest-vault/src/module/Guard.sol";
import {VaultLib, IVault} from "lib/yieldnest-vault/src/library/VaultLib.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

contract SafeGuard is BaseTransactionGuard, BaseModuleGuard, AccessControlUpgradeable {
    string public constant VERSION = "0.2.0";

    bytes32 public constant PROCESSOR_MANAGER_ROLE = keccak256("PROCESSOR_MANAGER_ROLE");
    bytes32 public constant GUARD_ADMIN_ROLE = keccak256("GUARD_ADMIN_ROLE");

    event CheckTransactionEnabledSet(bool enabled);
    event CheckModuleTransactionEnabledSet(bool enabled);

    /// @notice Storage struct for SafeGuard-specific state
    struct SafeGuardStorage {
        string name;
        bool checkTransactionEnabled;
        bool checkModuleTransactionEnabled;
    }

    /// @notice Get the SafeGuard storage using diamond storage pattern
    /// @return $ The SafeGuard storage reference
    function _getSafeGuardStorage() internal pure returns (SafeGuardStorage storage $) {
        assembly {
            // keccak256("yieldnest.storage.safeguard")
            $.slot := 0xdc30ccdf80e30c536bd9759df258d626d95ef881fdef2f7b8e27144d76dc25d9
        }
    }

    /// @notice Returns the name of this SafeGuard instance
    function name() public view returns (string memory) {
        return _getSafeGuardStorage().name;
    }

    /// @notice Returns whether transaction checking is enabled
    function checkTransactionEnabled() public view returns (bool) {
        return _getSafeGuardStorage().checkTransactionEnabled;
    }

    /// @notice Returns whether module transaction checking is enabled
    function checkModuleTransactionEnabled() public view returns (bool) {
        return _getSafeGuardStorage().checkModuleTransactionEnabled;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param _name The name for this SafeGuard instance.
     * @param _admin The address that will be granted the admin role.
     */
    function initialize(string calldata _name, address _admin) public initializer {
        __AccessControl_init();

        _getSafeGuardStorage().name = _name;

        // Grant roles to the admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROCESSOR_MANAGER_ROLE, _admin);
        _grantRole(GUARD_ADMIN_ROLE, _admin);

        _setCheckTransactionEnabled(true);
        _setCheckModuleTransactionEnabled(true);
    }

    /// TransactionGuard ///

    /**
     * @notice Called by the Safe contract before a transaction is executed.
     * @dev Reverts on empty calldata (data.length < 4). ETH transfers with empty data are blocked.
     * @dev DelegateCall is not blocked. Rules validate target+selector, but delegatecall executes
     *      the target's code in the Safe's context. Ensure rules don't permit delegatecall to
     *      contracts with dangerous fallback logic.
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation, /* operation */
        uint256, /* safeTxGas */
        uint256, /* baseGas */
        uint256, /* gasPrice */
        address, /* gasToken */
        address payable, /* refundReceiver */
        bytes memory, /* signatures */
        address /* executor */
    ) external view override {
        if (!_getSafeGuardStorage().checkTransactionEnabled) return;
        // calls back to itself to be able to pass in a calldata parameter. Less gas efficient.
        SafeGuard(address(this)).validateCall(to, value, data);
    }

    /**
     * @inheritdoc ITransactionGuard
     */
    function checkAfterExecution(bytes32, bool) external pure override {
        // No-op implementation
    }

    /**
     * @notice Called by the Safe contract before a module transaction is executed.
     * @dev Reverts on empty calldata (data.length < 4). ETH transfers with empty data are blocked.
     * @dev DelegateCall is not blocked. Rules validate target+selector, but delegatecall executes
     *      the target's code in the Safe's context. Ensure rules don't permit delegatecall to
     *      contracts with dangerous fallback logic.
     */
    function checkModuleTransaction(address to, uint256 value, bytes memory data, Enum.Operation, address)
        external
        view
        override
        returns (bytes32 moduleTxHash)
    {
        if (!_getSafeGuardStorage().checkModuleTransactionEnabled) return bytes32(0);
        // calls back to itself to be able to pass in a calldata parameter. Less gas efficient.
        SafeGuard(address(this)).validateCall(to, value, data);
        return bytes32(0);
    }

    /**
     * @inheritdoc IModuleGuard
     */
    function checkAfterModuleExecution(bytes32, bool) external pure override {
        // No-op implementation
    }

    /// VaultLib Guard Rules ///

    /**
     * @notice Enables or disables the transaction check.
     * @param enabled Whether the transaction check should be enabled.
     */
    function setCheckTransactionEnabled(bool enabled) public onlyRole(GUARD_ADMIN_ROLE) {
        _setCheckTransactionEnabled(enabled);
    }

    /**
     * @notice Enables or disables the module transaction check.
     * @param enabled Whether the module transaction check should be enabled.
     */
    function setCheckModuleTransactionEnabled(bool enabled) public onlyRole(GUARD_ADMIN_ROLE) {
        _setCheckModuleTransactionEnabled(enabled);
    }

    /**
     * @notice Internal function to set the checkTransactionEnabled flag.
     * @param enabled Whether the transaction check should be enabled.
     */
    function _setCheckTransactionEnabled(bool enabled) internal {
        _getSafeGuardStorage().checkTransactionEnabled = enabled;
        emit CheckTransactionEnabledSet(enabled);
    }

    /**
     * @notice Internal function to set the checkModuleTransactionEnabled flag.
     * @param enabled Whether the module transaction check should be enabled.
     */
    function _setCheckModuleTransactionEnabled(bool enabled) internal {
        _getSafeGuardStorage().checkModuleTransactionEnabled = enabled;
        emit CheckModuleTransactionEnabledSet(enabled);
    }

    /**
     * @notice Validates a transaction call against the guard rules
     * @param target The address of the target contract
     * @param value The amount of ETH being sent with the call
     * @param data The calldata of the transaction
     * @dev This function is called by the checkTransaction function to validate calls
     */
    function validateCall(address target, uint256 value, bytes calldata data) public view {
        Guard.validateCall(target, value, data);
    }

    /**
     * @notice Sets the processor rule for a given contract address and function signature.
     * @dev This function does not check for duplicate rules.
     * @param target The address of the target contract.
     * @param functionSig The function signature.
     * @param rule The function rule.
     */
    function setProcessorRules(
        address[] calldata target,
        bytes4[] calldata functionSig,
        IVault.FunctionRule[] calldata rule
    ) public virtual onlyRole(PROCESSOR_MANAGER_ROLE) {
        VaultLib.setProcessorRules(target, functionSig, rule);
    }

    /**
     * @notice Returns the function rule for a given contract address and function signature.
     * @param contractAddress The address of the contract.
     * @param funcSig The function signature.
     * @return FunctionRule The function rule.
     */
    function getProcessorRule(address contractAddress, bytes4 funcSig)
        public
        view
        virtual
        returns (IVault.FunctionRule memory)
    {
        return _getProcessorStorage().rules[contractAddress][funcSig];
    }

    /**
     * @notice Internal function to get the processor storage.
     * @return The processor storage.
     */
    function _getProcessorStorage() internal pure returns (IVault.ProcessorStorage storage) {
        return VaultLib.getProcessorStorage();
    }

    /// ERC165 ///

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseTransactionGuard, BaseModuleGuard, AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ITransactionGuard).interfaceId // 0xe6d7a83a
            || interfaceId == type(IModuleGuard).interfaceId // 0x58401ed8
            || interfaceId == type(IERC165).interfaceId // 0x01ffc9a7
            || interfaceId == type(IAccessControl).interfaceId;
    }
}
