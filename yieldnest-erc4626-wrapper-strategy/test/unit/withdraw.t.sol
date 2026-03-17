// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.sol";
import "forge-std/console.sol";

contract WithdrawUnitTest is BaseUnitTest {
    address internal alice = address(0xA11CE);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_withdraw_basic() public {
        // Arrange: give alice some tokens and deposit to the vault
        uint256 depositAmount = 1000e18;
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Act: withdraw half of the assets
        uint256 withdrawAmount = 500e18;
        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Assert: assets received
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmount, "Alice should receive withdrawn assets"
        );
        assertEq(aliceSharesBefore - aliceSharesAfter, withdrawAmount, "Shares burned should equal assets withdrawn");
    }

    function test_redeem_basic() public {
        // Arrange: give alice some tokens and deposit to the vault
        uint256 depositAmount = 1200e18;
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Act: redeem some shares
        uint256 sharesToRedeem = 600e18;
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        // Assert: Alice should receive assets equal to shares redeemed (1:1 for default mock)
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, sharesToRedeem, "Alice should receive correct assets"
        );
        assertEq(aliceSharesAfter, depositAmount - sharesToRedeem, "Alice's shares decrease by redeemed amount");
    }

    function test_withdraw_after_donation_to_vault() public {
        // Arrange: Alice deposits tokens
        uint256 depositAmount = 1000e18;
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Someone else donates tokens directly to the underlying ERC4626 vault
        address donor = address(0xBEEF);
        uint256 donationAmount = 500e18;
        deal(address(mockERC20), donor, donationAmount);
        vm.startPrank(donor);
        mockERC20.transfer(address(mockERC4626), donationAmount);
        vm.stopPrank();

        // Alice tries to withdraw half her assets
        uint256 withdrawAmount = 500e18;
        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        uint256 strategyRateBefore = stakedLPStrategy.convertToAssets(1e18);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // After donation, shares are worth more assets per share, so Alice should burn less shares than assets withdrawn
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmount, "Alice receives assets requested");

        // Each share is worth 1.5 assets now, so withdrawing 500 assets should require burning only ~333.333... shares
        uint256 expectedSharesBurned = (withdrawAmount * 1e18) / strategyRateBefore;
        // Integer math: expect approximation
        assertApproxEqAbs(
            aliceSharesBefore - aliceSharesAfter,
            expectedSharesBurned,
            1e3, // 1e3 wei precision since deposit amountis 1000e18
            "Shares burned should equal assets/pricePerShare after donation"
        );
    }

    function test_redeem_after_donation_to_vault() public {
        // Arrange: Alice deposits tokens
        uint256 depositAmount = 900e18;
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Someone donates tokens directly to the ERC4626 vault
        address donor = address(0xCAFE);
        uint256 donationAmount = 900e18;
        deal(address(mockERC20), donor, donationAmount);
        vm.startPrank(donor);
        mockERC20.transfer(address(mockERC4626), donationAmount);
        vm.stopPrank();

        assertApproxEqAbs(
            mockERC4626.convertToAssets(1e18),
            (depositAmount + donationAmount) * 1e18 / depositAmount,
            1,
            "Assets per share should be 1"
        );

        // Alice redeems half her shares
        uint256 sharesToRedeem = 450e18; // half of her shares
        uint256 assetsPerShare = mockERC4626.convertToAssets(1e18);
        uint256 expectedAssetsReceived = (sharesToRedeem * assetsPerShare) / 1e18;

        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        // Should receive the product of shares * asset/share at time of redemption
        assertApproxEqAbs(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore,
            expectedAssetsReceived,
            1, // 1 wei accuracy
            "Alice should receive all assets per redeemed shares, including donation gain"
        );
        assertEq(aliceSharesAfter, depositAmount - sharesToRedeem, "Her shares reduce by redeemed amount");
    }

    function testFuzz_withdraw_basic(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1e30);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Arrange: give alice some tokens and deposit to the vault
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Act: withdraw assets
        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Assert: assets received
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmount, "Alice should receive withdrawn assets"
        );
        assertEq(aliceSharesBefore - aliceSharesAfter, withdrawAmount, "Shares burned should equal assets withdrawn");
    }

    function testFuzz_redeem_basic(uint256 depositAmount, uint256 sharesToRedeem) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1e30);
        sharesToRedeem = bound(sharesToRedeem, 1, depositAmount);

        // Arrange: give alice some tokens and deposit to the vault
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        // Act: redeem some shares
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        // Assert: Alice should receive assets equal to shares redeemed (1:1 for default mock)
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, sharesToRedeem, "Alice should receive correct assets"
        );
        assertEq(aliceSharesAfter, depositAmount - sharesToRedeem, "Alice's shares decrease by redeemed amount");
    }

    function testFuzz_withdraw_after_donation_to_vault(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 withdrawAmount
    ) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1e30);
        donationAmount = bound(donationAmount, 1e18, 1e30);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Arrange: Alice deposits tokens
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        {
            uint256 rateBeforeDonation = stakedLPStrategy.convertToAssets(1e18);
            // Someone else donates tokens directly to the underlying ERC4626 vault
            address donor = address(0xBEEF);
            deal(address(mockERC20), donor, donationAmount);
            vm.startPrank(donor);
            mockERC20.transfer(address(mockERC4626), donationAmount);
            vm.stopPrank();

            assertGt(stakedLPStrategy.convertToAssets(1e18), rateBeforeDonation, "Rate should increase after donation");
        }

        // Alice tries to withdraw assets
        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        uint256 strategyRateBefore = stakedLPStrategy.convertToAssets(1e18);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // After donation, shares are worth more assets per share, so Alice should burn less shares than assets withdrawn
        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        assertEq(aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmount, "Alice receives assets requested");

        // Calculate expected shares burned based on the rate before withdrawal
        uint256 expectedSharesBurned = (withdrawAmount * 1e18) / strategyRateBefore;

        uint256 tolerance = 1;
        {
            // Round up to the nearest power of 10
            uint256 rawTolerance = depositAmount / 1e18;

            while (tolerance < rawTolerance) {
                tolerance *= 10;
            }
        }

        // Integer math: expect approximation
        assertApproxEqAbs(
            aliceSharesBefore - aliceSharesAfter,
            expectedSharesBurned,
            tolerance,
            "Shares burned should equal assets/pricePerShare after donation"
        );
    }

    function testFuzz_redeem_after_donation_to_vault(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 sharesToRedeem
    ) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1e18, 1e30);
        donationAmount = bound(donationAmount, 1e18, 1e30);
        sharesToRedeem = bound(sharesToRedeem, 1, depositAmount);

        // Arrange: Alice deposits tokens
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        {
            uint256 rateBeforeDonation = stakedLPStrategy.convertToAssets(1e18);
            // Someone donates tokens directly to the ERC4626 vault
            address donor = address(0xCAFE);
            deal(address(mockERC20), donor, donationAmount);
            vm.startPrank(donor);
            mockERC20.transfer(address(mockERC4626), donationAmount);
            vm.stopPrank();

            assertGt(stakedLPStrategy.convertToAssets(1e18), rateBeforeDonation, "Rate should increase after donation");
        }

        // Alice redeems shares
        uint256 assetsPerShare = stakedLPStrategy.convertToAssets(1e18);
        uint256 expectedAssetsReceived = (sharesToRedeem * assetsPerShare) / 1e18;

        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();

        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        uint256 tolerance = 1;
        {
            // Round up to the nearest power of 10
            uint256 rawTolerance = depositAmount / 1e18;

            while (tolerance < rawTolerance) {
                tolerance *= 10;
            }
        }

        // Should receive the product of shares * asset/share at time of redemption
        assertApproxEqAbs(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore,
            expectedAssetsReceived,
            tolerance,
            "Alice should receive all assets per redeemed shares, including donation gain"
        );
        assertEq(aliceSharesAfter, depositAmount - sharesToRedeem, "Her shares reduce by redeemed amount");
    }

    function test_withdraw_after_erc4626donation_to_vault() public {
        // Arrange: Alice deposits tokens into the strategy
        uint256 depositAmount = 1000e18;
        deal(address(mockERC20), alice, depositAmount);

        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 strategyRateBefore = stakedLPStrategy.convertToAssets(1e18);

        // Someone donates ERC4626 tokens (vault shares) directly to the strategy
        address donor = address(0xBEEF);
        uint256 donationAmount = 500e18;
        // First, mint underlying erc20 tokens to the donor
        deal(address(mockERC20), donor, donationAmount);

        // Donor approves and deposits underlying tokens to get ERC4626 vault shares, donates those shares to the strategy
        vm.startPrank(donor);
        mockERC20.approve(address(mockERC4626), donationAmount);
        uint256 vaultShares = mockERC4626.deposit(donationAmount, donor);
        // Now send the vault shares to the strategy
        mockERC4626.transfer(address(stakedLPStrategy), vaultShares);
        vm.stopPrank();

        uint256 strategyRateAfter = stakedLPStrategy.convertToAssets(1e18);
        assertGt(strategyRateAfter, strategyRateBefore, "Rate should increase after donation");

        // Alice tries to withdraw half of her original deposit
        uint256 withdrawAmount = 500e18;
        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        // Alice should receive the target assets
        assertEq(aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmount, "Alice receives withdrawn assets");

        // After the donation, shares are worth more, so Alice should burn fewer shares for the same asset withdrawal
        uint256 expectedSharesBurned = (withdrawAmount * 1e18) / strategyRateAfter;

        // Integer math, expect approximation
        uint256 tolerance = 1e3;
        assertApproxEqAbs(
            aliceSharesBefore - aliceSharesAfter,
            expectedSharesBurned,
            tolerance,
            "Shares burned should be assets/pricePerShare after donation"
        );
    }

    function testFuzz_withdraw_after_erc4626_donation(
        uint256 depositAmount,
        uint256 withdrawAmountFuzz,
        uint256 donationAmountFuzz
    ) public {
        // Bound depositAmount between 1000e18 and 1_000_000e18
        depositAmount = bound(depositAmount, 1000e18, 1_000_000e18);

        deal(address(mockERC20), alice, depositAmount);

        // Alice deposits into the strategy (not direct to underlying vault)
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 aliceSharesBefore = stakedLPStrategy.balanceOf(alice);
        uint256 strategyRateBefore = stakedLPStrategy.convertToAssets(1e18);

        // Bound and mint donation
        donationAmountFuzz = bound(donationAmountFuzz, 1e18, 500_000e18);
        address donor = address(0xBEEF);
        deal(address(mockERC20), donor, donationAmountFuzz);

        // The donor mints ERC4626 vault shares, then donates those shares (NOT underlying tokens) to the strategy
        vm.startPrank(donor);
        mockERC20.approve(address(mockERC4626), donationAmountFuzz);
        uint256 vaultShares = mockERC4626.deposit(donationAmountFuzz, donor);
        // Donate ERC4626 vault shares to the strategy, not the underlying asset
        mockERC4626.transfer(address(stakedLPStrategy), vaultShares);
        vm.stopPrank();

        uint256 strategyRateAfter = stakedLPStrategy.convertToAssets(1e18);
        assertGt(strategyRateAfter, strategyRateBefore, "Rate should increase after donation");

        // Fuzz withdraw amount between 1e18 and depositAmount
        withdrawAmountFuzz = bound(withdrawAmountFuzz, 1e18, depositAmount);

        uint256 aliceTokenBalanceBefore = mockERC20.balanceOf(alice);

        vm.startPrank(alice);
        stakedLPStrategy.withdraw(withdrawAmountFuzz, alice, alice);
        vm.stopPrank();

        uint256 aliceTokenBalanceAfter = mockERC20.balanceOf(alice);
        uint256 aliceSharesAfter = stakedLPStrategy.balanceOf(alice);

        // Verify Alice receives exactly the withdrawn assets
        assertEq(
            aliceTokenBalanceAfter - aliceTokenBalanceBefore, withdrawAmountFuzz, "Alice receives withdrawn assets"
        );

        uint256 tolerance = 1;
        {
            // Round up to the nearest power of 10
            uint256 rawTolerance = depositAmount / 1e18;

            while (tolerance < rawTolerance) {
                tolerance *= 10;
            }
        }

        // Verify shares burned is approximately assets/pricePerShare after donation
        uint256 expectedSharesBurned = (withdrawAmountFuzz * 1e18) / strategyRateAfter;
        assertApproxEqAbs(
            aliceSharesBefore - aliceSharesAfter,
            expectedSharesBurned,
            tolerance,
            "Shares burned should be assets/pricePerShare after donation"
        );
    }
}
