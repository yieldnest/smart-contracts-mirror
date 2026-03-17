// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {SafeGuard} from "src/SafeGuard.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVault} from "lib/yieldnest-vault/src/library/VaultLib.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {BaseRules} from "lib/yieldnest-vault/script/rules/BaseRules.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IValidator.sol";
import {Enum} from "lib/safe-smart-account/contracts/libraries/Enum.sol";
import {Guard} from "lib/yieldnest-vault/src/module/Guard.sol";
import {ITransactionGuard} from "lib/safe-smart-account/contracts/base/GuardManager.sol";
import {IModuleGuard} from "lib/safe-smart-account/contracts/base/ModuleManager.sol";
import {IERC165} from "lib/safe-smart-account/contracts/interfaces/IERC165.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract SafeGuardTest is Test {
    SafeGuard implementation;
    SafeGuard safeguard;
    ProxyAdmin admin;
    address adminAddress;
    address user;
    address processorManager;

    function setUp() public {
        // Set up accounts
        adminAddress = makeAddr("admin");
        user = makeAddr("user");
        processorManager = makeAddr("processorManager");

        // Deploy implementation
        implementation = new SafeGuard();

        TransparentUpgradeableProxy transparentProxy =
            new TransparentUpgradeableProxy(address(implementation), adminAddress, "");
        // Cast proxy to SafeGuard
        safeguard = SafeGuard(address(transparentProxy));

        safeguard.initialize("TestSafeGuard", adminAddress);

        // Grant PROCESSOR_MANAGER_ROLE and GUARD_ADMIN_ROLE to processorManager
        vm.startPrank(adminAddress);
        safeguard.grantRole(safeguard.PROCESSOR_MANAGER_ROLE(), processorManager);
        safeguard.grantRole(safeguard.GUARD_ADMIN_ROLE(), processorManager);
        vm.stopPrank();
    }

    function test_setProcessorRules_revertWhenCallerNotProcessorManager() public {
        // Create sample targets
        address mockToken = address(0x5678);

        // Use BaseRules to get predefined rules
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));

        // Prepare arrays for setProcessorRules
        address[] memory targets = new address[](1);
        bytes4[] memory functionSigs = new bytes4[](1);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](1);

        targets[0] = approvalRule.contractAddress;
        functionSigs[0] = approvalRule.funcSig;
        rules[0] = approvalRule.rule;

        // Call from unauthorized user (not processorManager)
        vm.startPrank(user);

        // Expect revert when caller doesn't have PROCESSOR_MANAGER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, safeguard.PROCESSOR_MANAGER_ROLE()
            )
        );
        safeguard.setProcessorRules(targets, functionSigs, rules);

        vm.stopPrank();
    }

    function test_setProcessorRules() public {
        // Create sample targets
        address mockContract = address(0x1234);
        address mockToken = address(0x5678);

        // Use BaseRules to get predefined rules
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));

        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = approvalRule;
        ruleParams[1] = depositRule;
        vm.startPrank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Verify the rules were set correctly
        IVault.FunctionRule memory retrievedRule0 =
            safeguard.getProcessorRule(approvalRule.contractAddress, approvalRule.funcSig);
        IVault.FunctionRule memory retrievedRule1 =
            safeguard.getProcessorRule(depositRule.contractAddress, depositRule.funcSig);

        // Assert rule 0 properties (approval rule)
        assertEq(retrievedRule0.isActive, true);
        assertEq(address(retrievedRule0.validator), address(0));
        assertEq(retrievedRule0.paramRules.length, 2);

        // Assert rule 1 properties (deposit rule)
        assertEq(retrievedRule1.isActive, true);
        assertEq(address(retrievedRule1.validator), address(0));
        assertEq(retrievedRule1.paramRules.length, 2);
    }

    function test_checkTransaction_revertsOnInactiveRule() public {
        // Create sample targets
        address mockContract = address(0x1234);
        address mockToken = address(0x5678);

        // Use BaseRules to get predefined rules
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);

        // Set up rules - but make depositRule inactive
        depositRule.rule.isActive = false;

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = approvalRule;
        ruleParams[1] = depositRule;

        vm.startPrank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Verify the rules were set correctly
        IVault.FunctionRule memory retrievedRule =
            safeguard.getProcessorRule(depositRule.contractAddress, depositRule.funcSig);
        assertEq(retrievedRule.isActive, false);

        // Create transaction data for the inactive rule (deposit function)
        bytes memory txData = abi.encodeWithSelector(depositRule.funcSig, 1000, user);

        // Expect revert when checking transaction with inactive rule
        vm.expectRevert(
            abi.encodeWithSelector(Guard.RuleNotActive.selector, depositRule.contractAddress, depositRule.funcSig)
        );
        safeguard.checkTransaction(
            depositRule.contractAddress, // to
            0, // value
            txData, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            address(this) // executor
        );
    }

    function test_checkTransaction_succeedsWithActiveRule() public {
        // Create sample targets
        address mockContract = address(0x1234);
        address mockToken = address(0x5678);

        // Use BaseRules to get predefined rules
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);

        // Make sure rules are active
        approvalRule.rule.isActive = true;
        depositRule.rule.isActive = true;

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = approvalRule;
        ruleParams[1] = depositRule;

        vm.startPrank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Verify the rules were set correctly
        IVault.FunctionRule memory retrievedRule =
            safeguard.getProcessorRule(depositRule.contractAddress, depositRule.funcSig);
        assertEq(retrievedRule.isActive, true);

        // Create transaction data for the active rule (deposit function)
        // The first parameter is uint256 amount, second is address receiver
        bytes memory txData = abi.encodeWithSelector(depositRule.funcSig, 1000, user);

        // This should not revert since the rule is active and parameters match the allowed values
        safeguard.checkTransaction(
            depositRule.contractAddress, // to
            0, // value
            txData, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            address(this) // executor
        );

        // Also test the approval rule
        bytes memory approvalData = abi.encodeWithSelector(approvalRule.funcSig, address(this), 500);

        // This should also not revert
        safeguard.checkTransaction(
            approvalRule.contractAddress, // to
            0, // value
            approvalData, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            address(this) // executor
        );
    }

    // --- initialize tests ---

    function test_initialize_setsCheckTransactionEnabled() public view {
        assertTrue(safeguard.checkTransactionEnabled(), "checkTransactionEnabled should be true after initialize");
    }

    function test_initialize_setsAdminRole() public view {
        assertTrue(
            safeguard.hasRole(safeguard.DEFAULT_ADMIN_ROLE(), adminAddress), "Admin should have DEFAULT_ADMIN_ROLE"
        );
    }

    function test_initialize_revertWhenCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        safeguard.initialize("TestSafeGuard", adminAddress);
    }

    function test_initialize_revertOnImplementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize("TestSafeGuard", adminAddress);
    }

    // --- setCheckTransactionEnabled tests ---

    function test_setCheckTransactionEnabled_revertWhenCallerNotGuardAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, safeguard.GUARD_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        safeguard.setCheckTransactionEnabled(false);
    }

    function test_setCheckTransactionEnabled_succeeds() public {
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);
        assertFalse(safeguard.checkTransactionEnabled(), "Should be disabled");

        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(true);
        assertTrue(safeguard.checkTransactionEnabled(), "Should be re-enabled");
    }

    // --- checkTransaction with disabled flag ---

    function test_checkTransaction_skipsValidationWhenDisabled() public {
        // Disable check
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);

        // Call checkTransaction with a target that has no rules — should not revert
        safeguard.checkTransaction(
            address(0xdead),
            0,
            abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            bytes(""),
            address(this)
        );
    }

    function test_checkTransaction_skipsValidationWithEmptyDataWhenDisabled() public {
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);

        // Empty data would normally revert due to data[:4] slice — should pass when disabled
        safeguard.checkTransaction(
            address(0xdead),
            1 ether,
            bytes(""),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            bytes(""),
            address(this)
        );
    }

    // --- supportsInterface tests ---

    function test_supportsInterface_ITransactionGuard() public view {
        assertTrue(safeguard.supportsInterface(type(ITransactionGuard).interfaceId));
    }

    function test_supportsInterface_IModuleGuard() public view {
        assertTrue(safeguard.supportsInterface(type(IModuleGuard).interfaceId));
    }

    function test_supportsInterface_IERC165() public view {
        assertTrue(safeguard.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsInterface_IAccessControl() public view {
        assertTrue(safeguard.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_supportsInterface_returnsFalseForUnknown() public view {
        assertFalse(safeguard.supportsInterface(bytes4(0xffffffff)));
    }

    // --- setProcessorRules edge cases ---

    function test_setProcessorRules_revertOnMismatchedArrayLengths() public {
        address[] memory targets = new address[](2);
        bytes4[] memory functionSigs = new bytes4[](1);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](2);

        targets[0] = address(0x1);
        targets[1] = address(0x2);
        functionSigs[0] = bytes4(0xdeadbeef);

        vm.prank(processorManager);
        vm.expectRevert(IVault.InvalidArray.selector);
        safeguard.setProcessorRules(targets, functionSigs, rules);
    }

    // --- getProcessorRule for nonexistent rule ---

    function test_getProcessorRule_returnsInactiveForUnsetRule() public view {
        IVault.FunctionRule memory rule = safeguard.getProcessorRule(address(0xdead), bytes4(0xdeadbeef));
        assertFalse(rule.isActive, "Unset rule should be inactive");
        assertEq(rule.paramRules.length, 0, "Unset rule should have no param rules");
        assertEq(address(rule.validator), address(0), "Unset rule should have no validator");
    }

    // --- Event emission tests ---

    function test_setProcessorRules_emitsSetProcessorRuleEvents() public {
        address mockToken = address(0x5678);
        address mockContract = address(0x1234);

        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = approvalRule;
        ruleParams[1] = depositRule;

        vm.startPrank(processorManager);
        vm.expectEmit(true, false, false, true);
        emit IVault.SetProcessorRule(approvalRule.contractAddress, approvalRule.funcSig, approvalRule.rule);
        vm.expectEmit(true, false, false, true);
        emit IVault.SetProcessorRule(depositRule.contractAddress, depositRule.funcSig, depositRule.rule);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();
    }

    // --- checkTransaction with unknown selector ---

    function test_checkTransaction_revertsOnUnknownSelector() public {
        // No rules set for this target/selector combination at all
        bytes memory txData = abi.encodeWithSelector(bytes4(0xcafebabe), uint256(42));

        vm.expectRevert(abi.encodeWithSelector(Guard.RuleNotActive.selector, address(0xbeef), bytes4(0xcafebabe)));
        safeguard.checkTransaction(
            address(0xbeef),
            0,
            txData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            bytes(""),
            address(this)
        );
    }

    // --- value parameter not validated ---

    function test_checkTransaction_valueNotValidated() public {
        // Set up an active rule
        address mockContract = address(0x1234);
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](1);
        ruleParams[0] = depositRule;

        vm.prank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);

        // Call with arbitrary ETH value — should NOT revert because value is not validated
        bytes memory txData = abi.encodeWithSelector(depositRule.funcSig, 1000, user);

        safeguard.checkTransaction(
            depositRule.contractAddress,
            999 ether, // large value — not validated by guard
            txData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            bytes(""),
            address(this)
        );
    }

    // --- checkModuleTransaction validates when enabled ---

    function test_checkModuleTransaction_validatesWhenEnabled() public {
        // checkModuleTransaction should revert on invalid call when enabled
        vm.expectRevert(abi.encodeWithSelector(Guard.RuleNotActive.selector, address(0xdead), bytes4(0xdeadbeef)));
        safeguard.checkModuleTransaction(
            address(0xdead),
            1 ether,
            abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1)),
            Enum.Operation.Call,
            address(0xbeef)
        );
    }

    function test_checkModuleTransaction_bypassesWhenDisabled() public {
        // Disable module transaction check
        vm.prank(processorManager);
        safeguard.setCheckModuleTransactionEnabled(false);

        // checkModuleTransaction should return bytes32(0) without validation
        bytes32 result = safeguard.checkModuleTransaction(
            address(0xdead),
            1 ether,
            abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1)),
            Enum.Operation.Call,
            address(0xbeef)
        );
        assertEq(result, bytes32(0), "checkModuleTransaction should return bytes32(0) when disabled");
    }

    // --- checkAfterExecution and checkAfterModuleExecution are no-ops ---

    function test_checkAfterExecution_doesNotRevert() public view {
        safeguard.checkAfterExecution(bytes32(uint256(1)), true);
        safeguard.checkAfterExecution(bytes32(uint256(1)), false);
    }

    function test_checkAfterModuleExecution_doesNotRevert() public view {
        safeguard.checkAfterModuleExecution(bytes32(uint256(1)), true);
        safeguard.checkAfterModuleExecution(bytes32(uint256(1)), false);
    }

    // --- Overwriting an active rule ---

    function test_setProcessorRules_overwritesExistingRule() public {
        address mockToken = address(0x5678);

        // Set an initial approval rule
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockToken, address(this));
        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](1);
        ruleParams[0] = approvalRule;

        vm.prank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);

        // Verify initial rule
        IVault.FunctionRule memory rule = safeguard.getProcessorRule(mockToken, approvalRule.funcSig);
        assertTrue(rule.isActive);
        assertEq(rule.paramRules[0].allowList[0], address(this), "Initial allowlist should contain address(this)");

        // Overwrite with a different allowlist
        address newSpender = makeAddr("newSpender");
        SafeRules.RuleParams memory newRule = BaseRules.getApprovalRule(mockToken, newSpender);
        ruleParams[0] = newRule;

        vm.prank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);

        // Verify overwritten rule
        IVault.FunctionRule memory updatedRule = safeguard.getProcessorRule(mockToken, approvalRule.funcSig);
        assertTrue(updatedRule.isActive);
        assertEq(updatedRule.paramRules[0].allowList[0], newSpender, "Allowlist should now contain newSpender");
        assertEq(updatedRule.paramRules[0].allowList.length, 1, "Allowlist should have exactly 1 entry");
    }

    // --- Multiple rules on same target ---

    function test_setProcessorRules_multipleRulesOnSameTarget() public {
        address mockContract = address(0x1234);

        // Set two different function rules for the same contract
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(mockContract, user);
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(mockContract, address(this));

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = depositRule;
        ruleParams[1] = approvalRule;

        vm.prank(processorManager);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);

        // Both rules should be independently retrievable
        IVault.FunctionRule memory retrievedDeposit = safeguard.getProcessorRule(mockContract, depositRule.funcSig);
        IVault.FunctionRule memory retrievedApproval = safeguard.getProcessorRule(mockContract, approvalRule.funcSig);

        assertTrue(retrievedDeposit.isActive, "Deposit rule should be active");
        assertTrue(retrievedApproval.isActive, "Approval rule should be active");

        // Verify they have distinct param rules
        assertEq(retrievedDeposit.paramRules[1].allowList[0], user, "Deposit receiver should be user");
        assertEq(
            retrievedApproval.paramRules[0].allowList[0], address(this), "Approval spender should be address(this)"
        );
    }

    // --- Fuzz test: disabled flag bypasses all validation ---

    function testFuzz_checkTransaction_skipsAllValidationWhenDisabled(
        address target,
        uint256 value,
        bytes4 selector,
        uint256 param
    ) public {
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);

        bytes memory txData = abi.encodeWithSelector(selector, param);

        // Should never revert regardless of target, value, selector, or params
        safeguard.checkTransaction(
            target,
            value,
            txData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            bytes(""),
            address(this)
        );
    }
}
