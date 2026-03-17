// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {console} from "forge-std/console.sol";

contract VaultBasicFunctionalityTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit_lp() public {
        uint256 depositAmount = 100e6;

        address alice = makeAddr("alice");

        deposit_lp(alice, depositAmount);

        uint256 lpBalance = IERC20(underlyingAsset).balanceOf(alice);
        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(targetVault, lpBalance);

        IERC4626(targetVault).deposit(lpBalance, alice);

        assertEq(IERC20(targetVault).balanceOf(alice), lpBalance, "Vault share balance mismatch");

        vm.stopPrank();
    }

    function test_initial_deposit_success() public {
        uint256 depositAmount = 100e6;

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        uint256 aliceShareBalance = IERC20(stakedLPStrategy).balanceOf(alice);

        assertEq(aliceShareBalance, shares, "Share amount mismatch after deposit");
        assertEq(aliceShareBalance, lpBalance, "Alice strategy share balance should match lpBalance");
        assertEq(
            IERC20(underlyingAsset).balanceOf(alice),
            0,
            "Alice's stakedao LP balance should be zero after strategy deposit"
        );
        assertEq(stakedLPStrategy.balanceOf(alice), lpBalance, "Alice's stakedao gauge balance mismatch");
        assertEq(stakedLPStrategy.totalAssets(), lpBalance, "Total assets mismatch after deposit");
        assertEq(stakedLPStrategy.totalSupply(), lpBalance, "Total supply mismatch after deposit");

        vm.stopPrank();
    }

    function testFuzz_initial_deposit_success(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 shares = stakedLPStrategy.deposit(lpBalance, alice);

        uint256 aliceShareBalance = IERC20(stakedLPStrategy).balanceOf(alice);

        vm.stopPrank();

        assertEq(aliceShareBalance, shares, "Share amount mismatch after fuzz deposit");

        assertEq(IERC20(underlyingAsset).balanceOf(alice), 0, "Alice's stakedao LP balance mismatch");

        assertEq(stakedLPStrategy.balanceOf(alice), lpBalance, "Alice's stakedao gauge balance mismatch");

        assertEq(stakedLPStrategy.totalAssets(), lpBalance, "Alice's stakedao gauge total assets mismatch");

        assertEq(stakedLPStrategy.totalSupply(), lpBalance, "Alice's stakedao gauge total supply mismatch");

        assertEq(
            IERC20(targetVault).balanceOf(address(stakedLPStrategy)), lpBalance, "Vault balance of stakedao LP mismatch"
        );
    }

    function test_initial_mint_success() public {
        uint256 mintAmount = 100e6;

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, mintAmount);

        uint256 lpBalance = deposit_lp(alice, mintAmount);

        assertEq(IERC20(underlyingAsset).balanceOf(alice), lpBalance, "Alice's stakedao LP balance mismatch");

        uint256 beforeTotalAssets = stakedLPStrategy.totalAssets();
        uint256 beforeTotalSupply = stakedLPStrategy.totalSupply();

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 desiredShares = stakedLPStrategy.previewDeposit(lpBalance);

        uint256 assetsDeposited = stakedLPStrategy.mint(desiredShares, alice);

        assertEq(IERC20(stakedLPStrategy).balanceOf(alice), desiredShares, "Alice's stakedao gauge balance mismatch");
        assertEq(assetsDeposited, lpBalance, "Assets deposited mismatch");

        uint256 afterTotalAssets = stakedLPStrategy.totalAssets();
        uint256 afterTotalSupply = stakedLPStrategy.totalSupply();

        assertEq(afterTotalAssets, beforeTotalAssets + lpBalance, "totalAssets did not increase by deposited assets");
        assertEq(afterTotalSupply, beforeTotalSupply + desiredShares, "totalSupply did not increase by minted shares");

        vm.stopPrank();
    }

    function test_fuzz_initial_mint(uint256 mintAmount) public {
        mintAmount = bound(mintAmount, 1000, 100_000 * 1e6);

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, mintAmount);

        uint256 lpBalance = deposit_lp(alice, mintAmount);

        uint256 beforeTotalAssets = stakedLPStrategy.totalAssets();
        uint256 beforeTotalSupply = stakedLPStrategy.totalSupply();

        vm.startPrank(alice);

        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);

        uint256 previewShares = stakedLPStrategy.previewDeposit(lpBalance);
        vm.assume(previewShares > 0);

        uint256 assetsRequired = stakedLPStrategy.mint(previewShares, alice);

        assertEq(IERC20(address(stakedLPStrategy)).balanceOf(alice), previewShares, "Share balance mismatch on mint");
        assertEq(assetsRequired, lpBalance, "Mint did not use all deposited LP assets");

        uint256 afterTotalAssets = stakedLPStrategy.totalAssets();
        uint256 afterTotalSupply = stakedLPStrategy.totalSupply();

        assertEq(
            afterTotalAssets, beforeTotalAssets + lpBalance, "totalAssets not increased correctly after mint (fuzz)"
        );
        assertEq(
            afterTotalSupply, beforeTotalSupply + previewShares, "totalSupply not increased correctly after mint (fuzz)"
        );
        vm.stopPrank();
    }
}
