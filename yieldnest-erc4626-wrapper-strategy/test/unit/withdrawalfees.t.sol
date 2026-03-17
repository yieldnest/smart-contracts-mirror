pragma solidity ^0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.sol";
import "forge-std/console.sol";

contract WithdrawalFeesUnitTest is BaseUnitTest {
    address internal alice = address(0xA11CE);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_set_withdrawal_fee_and_withdraw() public {
        // Setup: set withdrawal fee to 1% (100 basis points)
        vm.startPrank(ADMIN);
        uint64 withdrawalFee = 0.01e8;
        stakedLPStrategy.setBaseWithdrawalFee(withdrawalFee); // 1% fee
        vm.stopPrank();

        // Ensure the getter returns correct value
        assertEq(stakedLPStrategy.baseWithdrawalFee(), withdrawalFee, "Withdraw fee should be 1% (100 bps)");

        // Give 'alice' some tokens and deposit
        uint256 depositAmount = 1000e18;
        deal(address(mockERC20), alice, depositAmount);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);

        uint256 sharesToWithdraw = stakedLPStrategy.balanceOf(alice);
        // Withdraw to Alice - she should receive (99%) of the assets
        uint256 assetsPreview = stakedLPStrategy.previewRedeem(sharesToWithdraw);
        uint256 expectedAssets = (mockERC4626.convertToAssets(sharesToWithdraw) * (1e8 - withdrawalFee)) / 1e8;

        // previewRedeem should match expected

        // 990099009900990099009 !~= 990000000000000000000
        assertApproxEqRel(assetsPreview, expectedAssets, 1e15, "previewRedeem should consider withdrawal fee");

        uint256 aliceBalanceBefore = mockERC20.balanceOf(alice);
        // Actually redeem
        stakedLPStrategy.redeem(sharesToWithdraw, alice, alice);

        // Alice should receive 99% of assets (1% fee taken)
        uint256 aliceBalanceAfter = mockERC20.balanceOf(alice);
        uint256 receivedAssets = aliceBalanceAfter - aliceBalanceBefore;
        assertApproxEqRel(receivedAssets, expectedAssets, 1e15, "Alice should receive assets minus withdraw fee");

        vm.stopPrank();
    }

    function test_withdraw_withdrawal_fee() public {
        // Setup: set withdrawal fee to 1% (100 basis points)
        vm.startPrank(ADMIN);
        uint64 withdrawalFee = 0.01e8;
        stakedLPStrategy.setBaseWithdrawalFee(withdrawalFee); // 1% fee
        vm.stopPrank();

        // Ensure the getter returns correct value
        assertEq(stakedLPStrategy.baseWithdrawalFee(), withdrawalFee, "Withdraw fee should be 1% (100 bps)");

        // Give 'alice' some tokens and deposit
        uint256 depositAmount = 1000e18;
        deal(address(mockERC20), alice, depositAmount);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);

        // You can't withdraw all of it with withdraw - you can only withdraw up to previewRedeem(shares)
        uint256 shares = stakedLPStrategy.balanceOf(alice);

        // Compute the maximum assets Alice can withdraw using all her shares.
        uint256 maxAssetsToWithdraw = stakedLPStrategy.previewRedeem(shares);

        // Check previewWithdraw against this value.
        uint256 sharesPreview = stakedLPStrategy.previewWithdraw(maxAssetsToWithdraw);
        // previewWithdraw should match shares exactly when asking to withdraw previewRedeem(shares)
        assertEq(sharesPreview, shares, "previewWithdraw should return all shares for previewRedeem(shares)");

        uint256 aliceBalanceBefore = mockERC20.balanceOf(alice);

        // Check rate before withdraw
        uint256 rateBefore = stakedLPStrategy.convertToAssets(1e18);

        // Now, actually withdraw as much as possible using withdraw
        stakedLPStrategy.withdraw(maxAssetsToWithdraw, alice, alice);

        uint256 aliceBalanceAfter = mockERC20.balanceOf(alice);

        // She should receive exactly the previewRedeem result (all available post-fee assets)
        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            maxAssetsToWithdraw,
            "Alice balance should increase by maxAssetsToWithdraw"
        );

        // All shares should be burned (fully withdrawn)
        assertEq(stakedLPStrategy.balanceOf(alice), 0, "All shares should be burned");

        assertGt(
            stakedLPStrategy.convertToAssets(1e18), rateBefore, "Rate should increase after withdrawing with a fee"
        );
        assertEq(stakedLPStrategy.balanceOf(alice), 0, "Alice should have 0 shares after full withdrawal");

        vm.stopPrank();
    }
}
