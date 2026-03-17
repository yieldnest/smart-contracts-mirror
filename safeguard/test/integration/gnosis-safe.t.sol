// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {SafeGuard} from "src/SafeGuard.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ISafe} from "lib/safe-smart-account/contracts/interfaces/ISafe.sol";
import {IModuleManager} from "lib/safe-smart-account/contracts/interfaces/IModuleManager.sol";
import {Enum} from "lib/safe-smart-account/contracts/libraries/Enum.sol";
import {SafeProxyFactory} from "lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "lib/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {Safe} from "lib/safe-smart-account/contracts/Safe.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";
import {MockERC4626} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IValidator} from "lib/yieldnest-vault/src/interface/IValidator.sol";
import {BaseRules} from "lib/yieldnest-vault/script/rules/BaseRules.sol";
import {Guard} from "lib/yieldnest-vault/src/module/Guard.sol";
import {IGuardManager} from "lib/safe-smart-account/contracts/interfaces/IGuardManager.sol";
import {WETH9} from "lib/yieldnest-vault/test/unit/mocks/MockWETH.sol";
import {IWETH} from "lib/yieldnest-vault/test/interface/external/ethereum/IWETH.sol";
import {IOwnerManager} from "lib/safe-smart-account/contracts/interfaces/IOwnerManager.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract GnosisSafeTest is Test {
    SafeGuard implementation;
    SafeGuard safeguard;
    ProxyAdmin admin;
    address adminAddress;
    address user;
    address processorManager;

    // Gnosis Safe contracts
    Safe singleton;
    SafeProxyFactory factory;
    ISafe safe;

    // Owner addresses for the Safe
    address[] owners;
    uint256 threshold = 1;

    // Mock tokens
    MockERC20 mockToken;
    MockERC4626 mockVault;

    function setUp() public {
        // Set up accounts
        adminAddress = makeAddr("admin");
        user = makeAddr("user");
        processorManager = makeAddr("processorManager");

        // Create owner addresses for the Safe
        owners = new address[](1);
        owners[0] = user;

        // Deploy SafeGuard implementation and proxy
        implementation = new SafeGuard();
        TransparentUpgradeableProxy transparentProxy =
            new TransparentUpgradeableProxy(address(implementation), adminAddress, "");
        safeguard = SafeGuard(address(transparentProxy));
        safeguard.initialize("TestSafeGuard", adminAddress);

        // Grant PROCESSOR_MANAGER_ROLE and GUARD_ADMIN_ROLE to processorManager
        vm.startPrank(adminAddress);
        safeguard.grantRole(safeguard.PROCESSOR_MANAGER_ROLE(), processorManager);
        safeguard.grantRole(safeguard.GUARD_ADMIN_ROLE(), processorManager);
        vm.stopPrank();

        // Deploy Gnosis Safe contracts
        singleton = new Safe();
        factory = new SafeProxyFactory();

        // Deploy a new Safe
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0), // to
            bytes(""), // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            address(0) // paymentReceiver
        );

        SafeProxy safeProxy = factory.createProxyWithNonce(address(singleton), initializer, 0);
        safe = ISafe(address(safeProxy));

        // Deploy mock tokens
        mockToken = new MockERC20("Mock Token", "MTK");
        mockVault = new MockERC4626(mockToken, "Mock Vault", "MVT");

        addSafeGuardAsGuard();

        // Set up rules for approve and deposit
        vm.startPrank(processorManager);

        // Create rule for token approval using BaseRules
        SafeRules.RuleParams memory approvalRule = BaseRules.getApprovalRule(address(mockToken), address(mockVault));

        // Create rule for deposit
        SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(address(mockVault), address(safe));

        // Prepare array of rules
        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](2);
        ruleParams[0] = approvalRule;
        ruleParams[1] = depositRule;

        // Set the rules in the SafeGuard using the library function
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();
    }

    function addSafeGuardAsGuard() public {
        {
            // Prepare the transaction to set the guard
            bytes memory data = abi.encodeWithSelector(IGuardManager.setGuard.selector, address(safeguard));

            // Execute the transaction and verify the guard was set successfully
            bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);
            assertTrue(success, "Failed to set SafeGuard as guard");
        }
        // Prepare the transaction to set the module guard
    }

    function executeTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        bytes memory revertData
    ) internal returns (bool success) {
        vm.startPrank(user);

        // Create signature for the transaction
        bytes memory signature = abi.encodePacked(uint256(uint160(user)), uint256(0), uint8(1));

        // Execute the transaction
        if (revertData.length > 0) {
            vm.expectRevert(revertData);
        }
        success = safe.execTransaction(
            to,
            value,
            data,
            operation,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signature // signatures
        );

        vm.stopPrank();
        return success;
    }

    function executeTransaction(address to, uint256 value, bytes memory data, Enum.Operation operation)
        internal
        returns (bool success)
    {
        return executeTransaction(to, value, data, operation, new bytes(0));
    }

    function test_executeTransaction() public {
        // Mint mock tokens to the Gnosis Safe
        uint256 mintAmount = 1000 * 10 ** 18; // 1000 tokens
        vm.prank(address(safe));
        mockToken.mint(mintAmount);
        assertEq(mockToken.balanceOf(address(safe)), mintAmount, "Safe should have received tokens");

        // Execute approve transaction
        uint256 approveAmount = 500 * 10 ** 18; // 500 tokens
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), approveAmount);

        bool approveSuccess = executeTransaction(address(mockToken), 0, approveData, Enum.Operation.Call);
        assertTrue(approveSuccess, "Approve transaction failed");
        assertEq(mockToken.allowance(address(safe), address(mockVault)), approveAmount, "Allowance not set correctly");

        // Execute deposit transaction
        uint256 depositAmount = 300 * 10 ** 18; // 300 tokens
        bytes memory depositData = abi.encodeWithSelector(IERC4626.deposit.selector, depositAmount, address(safe));

        bool depositSuccess = executeTransaction(address(mockVault), 0, depositData, Enum.Operation.Call);
        assertTrue(depositSuccess, "Deposit transaction failed");

        // Verify deposit was successful
        assertEq(
            mockToken.balanceOf(address(safe)),
            mintAmount - depositAmount,
            "Token balance should be reduced after deposit"
        );
        assertEq(
            mockVault.balanceOf(address(safe)),
            depositAmount,
            "Safe should have received vault shares equal to deposit amount"
        );
    }

    function test_RevertWhenReceiverIsRandomAddress() public {
        // Setup: Deploy contracts and mint tokens
        address randomAddress = makeAddr("random");
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);
        assertEq(mockToken.balanceOf(address(safe)), mintAmount, "Safe should have received tokens");

        // Try to execute approve transaction with random address as receiver
        uint256 approveAmount = 500 * 10 ** 18;
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, mockVault, approveAmount);

        executeTransaction(address(mockToken), 0, approveData, Enum.Operation.Call);

        // Try to execute transfer transaction to random address
        bytes memory transferData = abi.encodeWithSelector(IERC4626.deposit.selector, approveAmount, randomAddress);

        executeTransaction(
            address(mockVault),
            0,
            transferData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.AddressNotInAllowlist.selector, randomAddress)
        );

        // Verify no tokens were transferred
        assertEq(mockToken.balanceOf(randomAddress), 0, "Random address should not receive any tokens");
        assertEq(mockToken.balanceOf(address(safe)), mintAmount, "Safe's token balance should remain unchanged");
    }

    function test_RevertWhenSignatureIsInvalid() public {
        // Setup: Deploy contracts and mint tokens
        address randomAddress = makeAddr("random");
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);
        assertEq(mockToken.balanceOf(address(safe)), mintAmount, "Safe should have received tokens");

        // Try to execute approve transaction with random address as receiver
        uint256 approveAmount = 500 * 10 ** 18;
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, mockVault, approveAmount);

        executeTransaction(address(mockToken), 0, approveData, Enum.Operation.Call);

        // Try to execute transfer transaction to address
        bytes memory transferData = abi.encodeWithSelector(IERC4626.mint.selector, approveAmount, address(safe));

        executeTransaction(
            address(mockVault),
            0,
            transferData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(mockVault), IERC4626.mint.selector)
        );

        // Verify no tokens were transferred
        assertEq(mockToken.balanceOf(randomAddress), 0, "Random address should not receive any tokens");
        assertEq(mockToken.balanceOf(address(safe)), mintAmount, "Safe's token balance should remain unchanged");
    }

    function test_RevertWhenETHTransfer() public {
        address recipient = makeAddr("recipient");

        // Fund the Safe with ETH
        vm.deal(address(safe), 1 ether);

        // Try to send ETH with empty calldata — guard slices data[:4] which reverts on empty data
        vm.startPrank(user);
        bytes memory signature = abi.encodePacked(uint256(uint160(user)), uint256(0), uint8(1));

        vm.expectRevert();
        safe.execTransaction(
            recipient,
            1 ether,
            bytes(""), // empty data — plain ETH transfer
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
        vm.stopPrank();

        // ETH should not have moved
        assertEq(address(safe).balance, 1 ether, "Safe should still hold its ETH");
        assertEq(recipient.balance, 0, "Recipient should have received nothing");
    }

    function test_WrapUnwrapAndTransferWETH() public {
        WETH9 weth = new WETH9();
        address recipient = makeAddr("recipient");
        uint256 wrapAmount = 1 ether;

        // Fund the Safe with ETH
        vm.deal(address(safe), 3 ether);

        // Set up rules: WETH deposit (wrap), WETH withdraw (unwrap), WETH transfer
        vm.startPrank(processorManager);

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](3);

        // Rule for WETH.deposit() — wrap ETH
        ruleParams[0] = BaseRules.getWethDepositRule(address(weth));

        // Rule for WETH.withdraw(uint256) — unwrap WETH
        ruleParams[1] = BaseRules.getWethWithdrawRule(address(weth));

        // Rule for WETH.transfer(address,uint256) — transfer WETH to recipient
        address[] memory transferAllowList = new address[](1);
        transferAllowList[0] = recipient;
        IVault.ParamRule[] memory transferParamRules = new IVault.ParamRule[](2);
        transferParamRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: transferAllowList});
        transferParamRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        ruleParams[2] = SafeRules.RuleParams({
            contractAddress: address(weth),
            funcSig: bytes4(keccak256("transfer(address,uint256)")),
            rule: IVault.FunctionRule({isActive: true, paramRules: transferParamRules, validator: IValidator(address(0))})
        });

        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // 1. Wrap ETH → WETH via deposit()
        bytes memory depositData = abi.encodeWithSelector(IWETH.deposit.selector);
        bool success = executeTransaction(address(weth), wrapAmount, depositData, Enum.Operation.Call);
        assertTrue(success, "WETH deposit (wrap) failed");
        assertEq(weth.balanceOf(address(safe)), wrapAmount, "Safe should hold WETH after wrap");
        assertEq(address(safe).balance, 3 ether - wrapAmount, "Safe ETH should decrease after wrap");

        // 2. Transfer WETH to recipient
        bytes memory transferData = abi.encodeWithSelector(IWETH.transfer.selector, recipient, wrapAmount);
        success = executeTransaction(address(weth), 0, transferData, Enum.Operation.Call);
        assertTrue(success, "WETH transfer failed");
        assertEq(weth.balanceOf(recipient), wrapAmount, "Recipient should hold WETH");
        assertEq(weth.balanceOf(address(safe)), 0, "Safe WETH balance should be zero");

        // 3. Wrap more ETH then unwrap it back via withdraw()
        success = executeTransaction(address(weth), wrapAmount, depositData, Enum.Operation.Call);
        assertTrue(success, "Second WETH deposit (wrap) failed");

        bytes memory withdrawData = abi.encodeWithSelector(IWETH.withdraw.selector, wrapAmount);
        success = executeTransaction(address(weth), 0, withdrawData, Enum.Operation.Call);
        assertTrue(success, "WETH withdraw (unwrap) failed");
        assertEq(weth.balanceOf(address(safe)), 0, "Safe should have no WETH after unwrap");
        assertEq(address(safe).balance, 2 ether, "Safe should have ETH back after unwrap");
    }

    function test_RevertWhenAddingOwner() public {
        address newOwner = makeAddr("newOwner");

        // Try to add a new owner — this is a self-call to the Safe, no rule exists for addOwnerWithThreshold
        bytes memory addOwnerData =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, newOwner, threshold);

        executeTransaction(
            address(safe),
            0,
            addOwnerData,
            Enum.Operation.Call,
            abi.encodeWithSelector(
                Guard.RuleNotActive.selector, address(safe), IOwnerManager.addOwnerWithThreshold.selector
            )
        );

        // Owner should not have been added
        assertFalse(safe.isOwner(newOwner), "New owner should not have been added");
    }

    function test_RevertWhenRemovingOwner() public {
        // user is the sole owner; prevOwner is SENTINEL (0x1) for the first entry in the linked list
        bytes memory removeOwnerData = abi.encodeWithSelector(IOwnerManager.removeOwner.selector, address(0x1), user, 1);

        executeTransaction(
            address(safe),
            0,
            removeOwnerData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(safe), IOwnerManager.removeOwner.selector)
        );

        // Owner should still be present
        assertTrue(safe.isOwner(user), "Owner should not have been removed");
    }

    function test_RevertWhenSwappingOwner() public {
        address newOwner = makeAddr("newOwner");

        // prevOwner is SENTINEL (0x1) for the first entry in the linked list
        bytes memory swapOwnerData =
            abi.encodeWithSelector(IOwnerManager.swapOwner.selector, address(0x1), user, newOwner);

        executeTransaction(
            address(safe),
            0,
            swapOwnerData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(safe), IOwnerManager.swapOwner.selector)
        );

        // Original owner should still be there, new one should not
        assertTrue(safe.isOwner(user), "Original owner should still be present");
        assertFalse(safe.isOwner(newOwner), "New owner should not have been added");
    }

    function test_RevertWhenChangingThreshold() public {
        // Try to change threshold — self-call, no rule exists
        bytes memory changeThresholdData = abi.encodeWithSelector(IOwnerManager.changeThreshold.selector, 1);

        executeTransaction(
            address(safe),
            0,
            changeThresholdData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(safe), IOwnerManager.changeThreshold.selector)
        );

        assertEq(safe.getThreshold(), threshold, "Threshold should not have changed");
    }

    function test_RevertWhenRemovingGuard() public {
        // Try to remove the guard — self-call to setGuard(address(0)), no rule exists
        bytes memory removeGuardData = abi.encodeWithSelector(IGuardManager.setGuard.selector, address(0));

        executeTransaction(
            address(safe),
            0,
            removeGuardData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(safe), IGuardManager.setGuard.selector)
        );
    }

    // --- Tests showing that disabling checkTransaction allows all Safe operations ---

    function _disableCheck() internal {
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);
    }

    function _enableCheck() internal {
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(true);
    }

    function test_AddOwnerWhenCheckDisabled() public {
        address newOwner = makeAddr("newOwner");
        _disableCheck();

        bytes memory data = abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, newOwner, threshold);
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);

        assertTrue(success, "addOwnerWithThreshold should succeed");
        assertTrue(safe.isOwner(newOwner), "New owner should have been added");
    }

    function test_RemoveOwnerWhenCheckDisabled() public {
        // First add a second owner so we can remove the original
        address newOwner = makeAddr("newOwner");
        _disableCheck();

        bytes memory addData = abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, newOwner, threshold);
        executeTransaction(address(safe), 0, addData, Enum.Operation.Call);
        assertTrue(safe.isOwner(newOwner), "New owner should have been added");

        // Now remove the new owner; new owner was inserted at the head, so prevOwner is SENTINEL
        bytes memory removeData =
            abi.encodeWithSelector(IOwnerManager.removeOwner.selector, address(0x1), newOwner, threshold);
        bool success = executeTransaction(address(safe), 0, removeData, Enum.Operation.Call);

        assertTrue(success, "removeOwner should succeed");
        assertFalse(safe.isOwner(newOwner), "Owner should have been removed");
    }

    function test_SwapOwnerWhenCheckDisabled() public {
        address newOwner = makeAddr("newOwner");
        _disableCheck();

        bytes memory data = abi.encodeWithSelector(IOwnerManager.swapOwner.selector, address(0x1), user, newOwner);
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);

        assertTrue(success, "swapOwner should succeed");
        assertFalse(safe.isOwner(user), "Old owner should have been removed");
        assertTrue(safe.isOwner(newOwner), "New owner should have been added");
    }

    function test_ChangeThresholdWhenCheckDisabled() public {
        // Add a second owner first so threshold 2 is valid
        address newOwner = makeAddr("newOwner");
        _disableCheck();

        bytes memory addData = abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, newOwner, threshold);
        executeTransaction(address(safe), 0, addData, Enum.Operation.Call);

        bytes memory data = abi.encodeWithSelector(IOwnerManager.changeThreshold.selector, 2);
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);

        assertTrue(success, "changeThreshold should succeed");
        assertEq(safe.getThreshold(), 2, "Threshold should have been changed to 2");
    }

    function test_RemoveGuardWhenCheckDisabled() public {
        _disableCheck();

        bytes memory data = abi.encodeWithSelector(IGuardManager.setGuard.selector, address(0));
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);

        assertTrue(success, "setGuard(0) should succeed");
    }

    function test_ETHTransferWhenCheckDisabled() public {
        address recipient = makeAddr("recipient");
        vm.deal(address(safe), 1 ether);
        _disableCheck();

        bool success = executeTransaction(recipient, 1 ether, bytes(""), Enum.Operation.Call);

        assertTrue(success, "ETH transfer should succeed");
        assertEq(recipient.balance, 1 ether, "Recipient should have received ETH");
        assertEq(address(safe).balance, 0, "Safe should have no ETH left");
    }

    function test_ReenableCheckAfterDisable() public {
        // Disable, do an admin op, re-enable, verify guard is enforced again
        address newOwner = makeAddr("newOwner");
        _disableCheck();

        bytes memory addData = abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, newOwner, threshold);
        bool success = executeTransaction(address(safe), 0, addData, Enum.Operation.Call);
        assertTrue(success, "addOwner should succeed while disabled");
        assertTrue(safe.isOwner(newOwner), "New owner should have been added while disabled");

        _enableCheck();

        // Now the guard should block again
        address anotherOwner = makeAddr("anotherOwner");
        bytes memory addData2 =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, anotherOwner, threshold);

        executeTransaction(
            address(safe),
            0,
            addData2,
            Enum.Operation.Call,
            abi.encodeWithSelector(
                Guard.RuleNotActive.selector, address(safe), IOwnerManager.addOwnerWithThreshold.selector
            )
        );

        assertFalse(safe.isOwner(anotherOwner), "Should be blocked after re-enabling check");
    }

    // --- Rule management tests ---

    function test_DeactivateRuleThenBlocks() public {
        // Approve rule is active from setUp — verify it works
        uint256 mintAmount = 1000e18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);

        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), 100e18);
        bool success = executeTransaction(address(mockToken), 0, approveData, Enum.Operation.Call);
        assertTrue(success, "Approve should succeed with active rule");

        // Deactivate the approve rule by overwriting it with isActive=false
        vm.startPrank(processorManager);
        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);
        address[] memory allowList = new address[](1);
        allowList[0] = address(mockVault);
        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](1);
        ruleParams[0] = SafeRules.RuleParams({
            contractAddress: address(mockToken),
            funcSig: IERC20.approve.selector,
            rule: IVault.FunctionRule({isActive: false, paramRules: paramRules, validator: IValidator(address(0))})
        });
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Now the same approve should be blocked
        executeTransaction(
            address(mockToken),
            0,
            approveData,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.RuleNotActive.selector, address(mockToken), IERC20.approve.selector)
        );
    }

    function test_UpdateAllowlistEnforcesNewList() public {
        // setUp has deposit rule allowing address(safe) as receiver
        uint256 mintAmount = 1000e18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);

        // Approve vault
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), mintAmount);
        executeTransaction(address(mockToken), 0, approveData, Enum.Operation.Call);

        // Deposit to safe succeeds (allowed by setUp rule)
        bytes memory depositData = abi.encodeWithSelector(IERC4626.deposit.selector, 100e18, address(safe));
        bool success = executeTransaction(address(mockVault), 0, depositData, Enum.Operation.Call);
        assertTrue(success, "Deposit to safe should succeed");

        // Update the deposit rule to only allow a different receiver
        address newReceiver = makeAddr("newReceiver");
        vm.startPrank(processorManager);
        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](1);
        ruleParams[0] = BaseRules.getDepositRule(address(mockVault), newReceiver);
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Now deposit to safe should be blocked (no longer in allowlist)
        bytes memory depositData2 = abi.encodeWithSelector(IERC4626.deposit.selector, 100e18, address(safe));
        executeTransaction(
            address(mockVault),
            0,
            depositData2,
            Enum.Operation.Call,
            abi.encodeWithSelector(Guard.AddressNotInAllowlist.selector, address(safe))
        );
    }

    // --- Access control in integration context ---

    function test_RevertWhenSafeOwnerTriesToDisableCheck() public {
        // Safe owner (user) should not be able to disable the check directly
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, safeguard.GUARD_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        safeguard.setCheckTransactionEnabled(false);
    }

    function test_RevertWhenSafeOwnerTriesToSetRules() public {
        address[] memory targets = new address[](1);
        bytes4[] memory sigs = new bytes4[](1);
        IVault.FunctionRule[] memory rules = new IVault.FunctionRule[](1);
        targets[0] = address(0x1);
        sigs[0] = bytes4(0xdeadbeef);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, safeguard.PROCESSOR_MANAGER_ROLE()
            )
        );
        vm.prank(user);
        safeguard.setProcessorRules(targets, sigs, rules);
    }

    // --- DelegateCall not checked ---

    function test_DelegateCallNotCheckedByGuard() public {
        // The guard ignores the operation parameter in checkTransaction, so it validates
        // delegatecalls the same way as regular calls — only checking target + funcSig.
        // A delegatecall to mockToken with an active approve rule passes the guard,
        // even though delegatecall executes in the Safe's context.
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), 100e18);

        // This passes the guard because approve rule is active for mockToken,
        // but it executes as delegatecall — the guard doesn't distinguish.
        bool success = executeTransaction(address(mockToken), 0, approveData, Enum.Operation.DelegateCall);
        assertTrue(success, "DelegateCall should pass the guard check since operation is not validated");
    }

    // --- ETH value sent alongside valid call ---

    function test_ETHValuePassedAlongsideValidCall() public {
        // The guard does not validate the `value` parameter.
        // ETH can be sent alongside a valid function call without restriction.
        WETH9 weth = new WETH9();
        vm.deal(address(safe), 5 ether);

        // Set up WETH deposit rule
        vm.startPrank(processorManager);
        SafeRules.RuleParams[] memory ruleParams = new SafeRules.RuleParams[](1);
        ruleParams[0] = BaseRules.getWethDepositRule(address(weth));
        SafeRules.setProcessorRules(IVault(address(safeguard)), ruleParams, true);
        vm.stopPrank();

        // Send 3 ETH with WETH deposit — guard doesn't limit the amount
        bytes memory depositData = abi.encodeWithSelector(IWETH.deposit.selector);
        bool success = executeTransaction(address(weth), 3 ether, depositData, Enum.Operation.Call);

        assertTrue(success, "Should succeed with arbitrary ETH value");
        assertEq(weth.balanceOf(address(safe)), 3 ether, "Safe should hold 3 WETH");
        assertEq(address(safe).balance, 2 ether, "Safe should have 2 ETH remaining");
    }

    // --- checkModuleTransaction validation ---

    function test_CheckModuleTransactionValidatesCall() public {
        // checkModuleTransaction now validates calls when enabled
        // Valid call should return bytes32(0)
        bytes32 result = safeguard.checkModuleTransaction(
            address(mockToken),
            0,
            abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), 100e18),
            Enum.Operation.Call,
            address(0xbeef)
        );
        assertEq(result, bytes32(0), "Valid module transaction should return bytes32(0)");
    }

    function test_CheckModuleTransactionRevertsOnInvalidCall() public {
        // Invalid call should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Guard.RuleNotActive.selector, address(safe), IOwnerManager.addOwnerWithThreshold.selector
            )
        );
        safeguard.checkModuleTransaction(
            address(safe),
            0,
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, address(0xdead), 1),
            Enum.Operation.Call,
            address(0xbeef)
        );
    }

    function test_CheckModuleTransactionBypassedWhenDisabled() public {
        // Disable module transaction check
        vm.prank(processorManager);
        safeguard.setCheckModuleTransactionEnabled(false);

        // Invalid call should now pass (returns bytes32(0) without validation)
        bytes32 result = safeguard.checkModuleTransaction(
            address(safe),
            0,
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, address(0xdead), 1),
            Enum.Operation.Call,
            address(0xbeef)
        );
        assertEq(result, bytes32(0), "Module transaction should bypass validation when disabled");
    }

    // --- Full module integration tests ---

    function _addModuleToSafe(address module) internal {
        // Disable check temporarily to add module
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);

        bytes memory data = abi.encodeWithSelector(IModuleManager.enableModule.selector, module);
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);
        assertTrue(success, "Failed to enable module");

        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(true);
    }

    function _setModuleGuard() internal {
        // Disable check temporarily to set module guard
        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(false);

        bytes memory data = abi.encodeWithSelector(IModuleManager.setModuleGuard.selector, address(safeguard));
        bool success = executeTransaction(address(safe), 0, data, Enum.Operation.Call);
        assertTrue(success, "Failed to set module guard");

        vm.prank(processorManager);
        safeguard.setCheckTransactionEnabled(true);
    }

    function test_ModuleExecutesValidTransaction() public {
        address module = makeAddr("module");
        _addModuleToSafe(module);
        _setModuleGuard();

        // Mint tokens to the Safe
        uint256 mintAmount = 1000e18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);

        // Module executes a valid approve transaction
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(mockVault), 100e18);

        vm.prank(module);
        bool success = safe.execTransactionFromModule(address(mockToken), 0, approveData, Enum.Operation.Call);
        assertTrue(success, "Module should execute valid transaction");
        assertEq(mockToken.allowance(address(safe), address(mockVault)), 100e18, "Allowance should be set");
    }

    function test_ModuleBlockedOnInvalidTransaction() public {
        address module = makeAddr("module");
        _addModuleToSafe(module);
        _setModuleGuard();

        // Module tries to execute an invalid transaction (no rule for addOwner)
        bytes memory addOwnerData =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, makeAddr("newOwner"), 1);

        vm.prank(module);
        vm.expectRevert(
            abi.encodeWithSelector(
                Guard.RuleNotActive.selector, address(safe), IOwnerManager.addOwnerWithThreshold.selector
            )
        );
        safe.execTransactionFromModule(address(safe), 0, addOwnerData, Enum.Operation.Call);
    }

    function test_ModuleBypassesGuardWhenCheckDisabled() public {
        address module = makeAddr("module");
        _addModuleToSafe(module);
        _setModuleGuard();

        // Disable module transaction check
        vm.prank(processorManager);
        safeguard.setCheckModuleTransactionEnabled(false);

        // Module can now execute any transaction
        bytes memory addOwnerData =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, makeAddr("newOwner"), 1);

        vm.prank(module);
        bool success = safe.execTransactionFromModule(address(safe), 0, addOwnerData, Enum.Operation.Call);
        assertTrue(success, "Module should bypass guard when check disabled");
        assertTrue(safe.isOwner(makeAddr("newOwner")), "New owner should have been added");
    }

    function test_ModuleAndOwnerTransactionsIndependentlyControlled() public {
        address module = makeAddr("module");
        _addModuleToSafe(module);
        _setModuleGuard();

        // Mint tokens
        uint256 mintAmount = 1000e18;
        vm.prank(address(safe));
        mockToken.mint(mintAmount);

        // Disable only module check
        vm.prank(processorManager);
        safeguard.setCheckModuleTransactionEnabled(false);

        // Module can execute invalid transaction
        bytes memory addOwnerData =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, makeAddr("newOwner"), 1);
        vm.prank(module);
        bool success = safe.execTransactionFromModule(address(safe), 0, addOwnerData, Enum.Operation.Call);
        assertTrue(success, "Module should bypass guard");

        // Owner transaction is still checked
        address anotherOwner = makeAddr("anotherOwner");
        bytes memory addOwnerData2 =
            abi.encodeWithSelector(IOwnerManager.addOwnerWithThreshold.selector, anotherOwner, 1);
        executeTransaction(
            address(safe),
            0,
            addOwnerData2,
            Enum.Operation.Call,
            abi.encodeWithSelector(
                Guard.RuleNotActive.selector, address(safe), IOwnerManager.addOwnerWithThreshold.selector
            )
        );
        assertFalse(safe.isOwner(anotherOwner), "Owner transaction should still be blocked");
    }

    // --- Multiple rules set and queried correctly ---

    function test_GetProcessorRuleReturnsCorrectData() public view {
        // Verify rules set in setUp are retrievable and correct
        IVault.FunctionRule memory approveRule = safeguard.getProcessorRule(address(mockToken), IERC20.approve.selector);
        assertTrue(approveRule.isActive, "Approve rule should be active");
        assertEq(approveRule.paramRules.length, 2, "Approve rule should have 2 param rules");
        assertEq(approveRule.paramRules[0].allowList.length, 1, "First param should have 1 allowed address");
        assertEq(approveRule.paramRules[0].allowList[0], address(mockVault), "Allowed spender should be mockVault");

        IVault.FunctionRule memory depositRule =
            safeguard.getProcessorRule(address(mockVault), IERC4626.deposit.selector);
        assertTrue(depositRule.isActive, "Deposit rule should be active");
        assertEq(depositRule.paramRules.length, 2, "Deposit rule should have 2 param rules");
    }
}
