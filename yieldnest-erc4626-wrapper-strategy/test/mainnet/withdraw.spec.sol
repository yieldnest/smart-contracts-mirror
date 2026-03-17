// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract VaultBasicFunctionalityTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_initial_withdraw_success(uint256 depositAmount, uint256 withdrawShares) public {
        // Fuzz deposit bounds: 1 USDC min, 1_000_000 USDC max (6 decimals)
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        uint256 aliceShareBalance = IERC20(stakedLPStrategy).balanceOf(alice);

        assertEq(aliceShareBalance, shares, "Share amount mismatch after fuzz deposit");

        // Bound withdrawShares between 0 and shares
        withdrawShares = bound(withdrawShares, 1, shares);

        uint256 preLpBalance = IERC20(underlyingAsset).balanceOf(alice);
        uint256 preStakeDaoBalance = IERC20(targetVault).balanceOf(address(stakedLPStrategy));

        uint256 assetsWithdrawn = stakedLPStrategy.withdraw(withdrawShares, alice, alice);

        // LP tokens should increase by at least assetsWithdrawn
        uint256 postLpBalance = IERC20(underlyingAsset).balanceOf(alice);
        assertEq(
            postLpBalance,
            preLpBalance + assetsWithdrawn,
            "LP token balance did not increase as expected after withdraw"
        );

        // Alice's share balance should reduce exactly by withdrawn shares
        uint256 aliceBalanceAfter = IERC20(stakedLPStrategy).balanceOf(alice);
        assertEq(aliceBalanceAfter, shares - withdrawShares, "Share balance did not decrease by withdrawn shares");

        // Assert the StakeDao gauge LP balance in the vault decreased by assetsWithdrawn
        uint256 postStakeDaoBalance = IERC20(targetVault).balanceOf(address(stakedLPStrategy));
        assertEq(
            postStakeDaoBalance,
            preStakeDaoBalance - assetsWithdrawn,
            "StakeDao LP balance in vault did not decrease by withdrawn amount"
        );

        vm.stopPrank();
    }

    function test_fuzz_initial_redeem_success(uint256 depositAmount, uint256 redeemAmount) public {
        // Fuzz deposit bounds: 1 USDC min, 1_000_000 USDC max (6 decimals)
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        uint256 aliceShareBalance = IERC20(stakedLPStrategy).balanceOf(alice);

        assertEq(aliceShareBalance, shares, "Share amount mismatch after fuzz deposit");

        redeemAmount = bound(redeemAmount, 1, depositAmount);

        uint256 preLpBalance = IERC20(underlyingAsset).balanceOf(alice);
        uint256 preStakeDaoBalance = IERC20(targetVault).balanceOf(address(stakedLPStrategy));

        uint256 assetsRedeemed = stakedLPStrategy.redeem(shares, alice, alice);

        // LP tokens should increase by exactly assetsRedeemed
        uint256 postLpBalance = IERC20(underlyingAsset).balanceOf(alice);
        assertEq(
            postLpBalance, preLpBalance + assetsRedeemed, "LP token balance did not increase as expected after redeem"
        );

        // Alice's share balance should go to zero (all shares redeemed)
        uint256 aliceBalanceAfter = IERC20(stakedLPStrategy).balanceOf(alice);
        assertEq(aliceBalanceAfter, 0, "Share balance should be zero after redeem");

        // Assert the StakeDao gauge LP balance in the vault decreased by assetsRedeemed
        uint256 postStakeDaoBalance = IERC20(targetVault).balanceOf(address(stakedLPStrategy));
        assertEq(
            postStakeDaoBalance,
            preStakeDaoBalance - assetsRedeemed,
            "StakeDao LP balance in vault did not decrease by redeemed amount"
        );

        vm.stopPrank();
    }

    function test_withdraw_single_sided() public {
        address alice = makeAddr("alice");

        uint256 depositAmount = 100e6;
        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);
        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        assertEq(IERC20(stakedLPStrategy).balanceOf(alice), shares, "Alice's strategy shares balance mismatch");

        stakedLPStrategy.approve(address(strategyAdapter), shares);

        uint256 withdrawSingleSidedAmount = 1e18;

        uint256 redeemableAmount = strategyAdapter.previewWithdrawSingleSided(withdrawSingleSidedAmount);

        // Withdraw all shares single-sided (receiving USDC)
        strategyAdapter.withdrawSingleSided(withdrawSingleSidedAmount, 0);

        address redeemableAsset = ICurvePool(underlyingAsset).coins(uint256(uint128(strategyAdapter.curveAssetIndex())));

        assertEq(IERC20(redeemableAsset).balanceOf(alice), redeemableAmount, "Alice's USDC balance mismatch");

        assertGt(IERC20(redeemableAsset).balanceOf(alice), 1e6, "Alice's USDC balance mismatch");

        vm.stopPrank();
    }

    function test_fuzz_withdraw_single_sided(uint256 depositAmount, uint256 withdrawAmount) public {
        // depositAmount: fuzz the deposit in USDC
        // withdrawAmount: fuzz the single-sided withdraw in shares

        address alice = makeAddr("alice");
        // Constrain inputs to reasonable values
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6); // Between $1 and $1,000,000 USDC
        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        // Alice must have >0 LP balance to continue
        vm.assume(lpBalance > 0);

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);
        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        assertEq(IERC20(stakedLPStrategy).balanceOf(alice), shares, "Alice's strategy shares balance mismatch");

        stakedLPStrategy.approve(address(strategyAdapter), shares);

        // Constrain withdrawAmount to Alice's available shares
        withdrawAmount = bound(withdrawAmount, 1, shares);
        address redeemableAsset = ICurvePool(underlyingAsset).coins(uint256(uint128(strategyAdapter.curveAssetIndex())));

        uint256 aliceRedeemableAssetBefore = IERC20(redeemableAsset).balanceOf(alice);

        uint256 redeemableAmount = strategyAdapter.previewWithdrawSingleSided(withdrawAmount);

        strategyAdapter.withdrawSingleSided(withdrawAmount, 0);
        // Check Alice received USDC
        assertEq(
            IERC20(redeemableAsset).balanceOf(alice),
            aliceRedeemableAssetBefore + redeemableAmount,
            "USDC received does not match preview"
        );

        // Check shares decreased
        uint256 aliceSharesAfter = IERC20(stakedLPStrategy).balanceOf(alice);
        assertEq(aliceSharesAfter, shares - withdrawAmount, "Alice's shares didn't decrease by withdrawn shares");

        vm.stopPrank();
    }

    function test_withdraw_after_deposit_and_donation() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // increase the max total assets decrease ratio to 10 ether to allow for large donations
        setMaxTotalAssetsIncreaseRatio(address(stakedLPStrategy), 10 ether);

        // Alice and Bob are both funded with USDC to mint LP tokens
        uint256 depositAmount = 100_000e6;
        deal(MC.USDC, alice, depositAmount);
        deal(MC.USDC, bob, depositAmount);

        // Alice receives LP tokens and deposits them into the strategy
        uint256 aliceLp = deposit_lp(alice, depositAmount);
        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), aliceLp);
        uint256 aliceShares = stakedLPStrategy.deposit(aliceLp, alice);
        vm.stopPrank();

        // Bob mints LP tokens, but DONATES them directly to the vault (does not call deposit)
        uint256 bobLp = deposit_lp(bob, depositAmount);
        // Send LP directly to the strategy, increasing totalAssets but not shares
        deal(underlyingAsset, bob, bobLp);
        vm.startPrank(bob);
        IERC20(underlyingAsset).transfer(address(stakedLPStrategy), bobLp);
        vm.stopPrank();

        stakedLPStrategy.processAccounting();

        // At this point alice has all the shares, but the vault has double the assets
        uint256 totalAssets = stakedLPStrategy.totalAssets();
        assertEq(totalAssets, aliceLp + bobLp, "Total assets should include Alice's deposit and Bob's donation");
        assertEq(stakedLPStrategy.totalSupply(), aliceShares, "Total supply should only be Alice's shares");

        // Alice withdra    ws all her shares for LP tokens
        vm.startPrank(alice);
        uint256 aliceInitialShares = stakedLPStrategy.balanceOf(alice);

        uint256 aliceLpBalanceBefore = IERC20(underlyingAsset).balanceOf(alice);

        // previewRedeem: how many LP tokens should Alice receive for redeeming all her shares?
        uint256 previewAssets = stakedLPStrategy.previewRedeem(aliceInitialShares);

        uint256 withdrawn = stakedLPStrategy.redeem(aliceInitialShares, alice, alice);

        assertEq(withdrawn, previewAssets, "Alice withdrawn LP should match previewRedeem");
        assertEq(stakedLPStrategy.balanceOf(alice), 0, "Alice should have 0 shares after redeeming all");

        // Alice gets more than her original deposit, due to Bob's donation
        uint256 aliceLpBalanceAfter = IERC20(underlyingAsset).balanceOf(alice);
        assertGt(aliceLpBalanceAfter - aliceLpBalanceBefore, aliceLp, "Alice profit includes Bob's donation");

        // The strategy vault should now have only Bob's donation (since Alice withdrew her share)
        assertEq(stakedLPStrategy.totalAssets(), totalAssets - withdrawn, "Vault assets should decrease by withdrawn");
        assertEq(stakedLPStrategy.totalSupply(), 0, "All shares burned after Alice's withdrawal");
        vm.stopPrank();
    }

    function test_redeem_total_assets_and_share_supply_handles_asset_donation() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        setMaxTotalAssetsIncreaseRatio(address(stakedLPStrategy), 1 ether);

        // Alice and Bob are both funded with USDC to mint LP tokens
        uint256 depositAmount = 100_000e6;
        deal(MC.USDC, alice, depositAmount);
        deal(MC.USDC, bob, depositAmount);

        // Alice receives LP tokens and deposits them into the strategy
        uint256 aliceLp = deposit_lp(alice, depositAmount);
        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), aliceLp);
        uint256 aliceShares = stakedLPStrategy.deposit(aliceLp, alice);
        vm.stopPrank();

        // Bob mints LP tokens, but DONATES them directly to the vault (does not call deposit)
        uint256 bobLp = deposit_lp(bob, depositAmount);
        // Send LP directly to the strategy, increasing totalAssets but not shares
        deal(underlyingAsset, bob, bobLp);
        vm.startPrank(bob);
        IERC20(underlyingAsset).transfer(address(stakedLPStrategy), bobLp);
        vm.stopPrank();

        stakedLPStrategy.processAccounting();

        // At this point alice has all the shares, but the vault has double the assets
        uint256 totalAssets = stakedLPStrategy.totalAssets();
        assertEq(totalAssets, aliceLp + bobLp, "Total assets should include Alice's deposit and Bob's donation");
        assertEq(stakedLPStrategy.totalSupply(), aliceShares, "Total supply should only be Alice's shares");

        // Alice redeems all her shares for LP tokens
        vm.startPrank(alice);
        uint256 aliceInitialShares = stakedLPStrategy.balanceOf(alice);

        uint256 aliceLpBalanceBefore = IERC20(underlyingAsset).balanceOf(alice);

        // previewRedeem: how many LP tokens should Alice receive for redeeming all her shares?
        uint256 previewAssets = stakedLPStrategy.previewRedeem(aliceInitialShares);

        uint256 withdrawn = stakedLPStrategy.redeem(aliceInitialShares, alice, alice);

        assertEq(withdrawn, previewAssets, "Alice withdrawn LP should match previewRedeem");
        assertEq(stakedLPStrategy.balanceOf(alice), 0, "Alice should have 0 shares after redeeming all");

        // Alice gets more than her original deposit, due to Bob's donation
        uint256 aliceLpBalanceAfter = IERC20(underlyingAsset).balanceOf(alice);
        assertGt(aliceLpBalanceAfter - aliceLpBalanceBefore, aliceLp, "Alice profit includes Bob's donation");

        // The strategy vault should now have only Bob's donation (since Alice withdrew her share)
        assertEq(stakedLPStrategy.totalAssets(), totalAssets - withdrawn, "Vault assets should decrease by withdrawn");
        assertEq(stakedLPStrategy.totalSupply(), 0, "All shares burned after Alice's redeem");
        vm.stopPrank();
    }

    function test_deposit_donation_and_another_deposit() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        // increase the max total assets decrease ratio to 1 ether to allow for large donations
        setMaxTotalAssetsIncreaseRatio(address(stakedLPStrategy), 1 ether);

        uint256 depositAmount = 100_000e6;
        uint256 donationAmount = 50_000e6;

        // 1. Alice: deposit
        deal(MC.USDC, alice, depositAmount);
        uint256 aliceLp = deposit_lp(alice, depositAmount);

        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), aliceLp);
        uint256 aliceShares = stakedLPStrategy.deposit(aliceLp, alice);
        vm.stopPrank();

        // 2. Bob: DONATES directly to LP vault (does not call deposit, just increases vault assets)
        deal(MC.USDC, bob, donationAmount);
        uint256 bobLp = deposit_lp(bob, donationAmount);
        vm.startPrank(bob);
        IERC20(underlyingAsset).transfer(address(stakedLPStrategy), bobLp);
        vm.stopPrank();

        stakedLPStrategy.processAccounting();

        // Record state after donation
        assertEq(stakedLPStrategy.totalAssets(), aliceLp + bobLp, "Total assets should reflect Alice's and Bob's");
        assertEq(stakedLPStrategy.totalSupply(), aliceShares, "Supply only reflects Alice's shares");

        // 3. Charlie: fresh deposit after donation
        deal(MC.USDC, charlie, depositAmount);
        uint256 charlieLp = deposit_lp(charlie, depositAmount);

        vm.startPrank(charlie);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), charlieLp);

        // Record previewShares for Charlie
        uint256 charliePreviewShares = stakedLPStrategy.previewDeposit(charlieLp);
        // Next deposit after donation should get fewer shares per asset than Alice
        uint256 charlieShares = stakedLPStrategy.deposit(charlieLp, charlie);
        vm.stopPrank();

        // 4. Check: Charlie received <charliePreviewShares> shares (should match)
        assertEq(charlieShares, charliePreviewShares, "Charlie should get previewed shares for post-donation deposit");

        // Since shares are distributed proportionally, Charlie's shares should be less than Alice's for equal depositAmount
        assertLt(
            charlieShares,
            aliceShares,
            "Charlie should receive fewer shares than Alice for the same deposit, since supply increased due to donation"
        );

        assertEq(
            stakedLPStrategy.totalAssets(),
            aliceLp + bobLp + charlieLp,
            "Vault total assets reflect all deposits and donations"
        );
        assertEq(
            stakedLPStrategy.totalSupply(),
            aliceShares + charlieShares,
            "Total supply reflects both real deposits, not donation"
        );

        // 5. Alice withdraws -- should receive more than her original deposit due to Bob's donation
        vm.startPrank(alice);
        uint256 aliceWithdrawn = stakedLPStrategy.redeem(aliceShares, alice, alice);
        vm.stopPrank();

        // Alice should get at least her preview value, which should be higher than aliceLp
        assertApproxEqAbs(
            aliceWithdrawn, stakedLPStrategy.previewRedeem(aliceShares), 3, "Actual asset redeemed matches preview"
        );
        assertGt(aliceWithdrawn, aliceLp, "Alice's redeemed assets should be increased by original donation");

        // 6. Charlie withdraws -- gets his proportional share
        vm.startPrank(charlie);
        uint256 charliePreviewAssets = stakedLPStrategy.previewRedeem(charlieShares);
        uint256 charlieWithdrawn = stakedLPStrategy.redeem(charlieShares, charlie, charlie);
        vm.stopPrank();

        assertEq(charlieWithdrawn, charliePreviewAssets, "Charlie's redeemed assets match preview");
        // He will also get a small boost attributable to the donation

        // 7. Vault: all assets should now be gone, only any remainder (dust) from rounding
        assertLe(
            stakedLPStrategy.totalAssets(),
            2, // there may be 1 or 2 wei (dust) left due to rounding/truncation
            "Vault assets after all shares burned should be dust"
        );
        assertEq(stakedLPStrategy.totalSupply(), 0, "Total supply is zero after all withdraws");
    }
}
