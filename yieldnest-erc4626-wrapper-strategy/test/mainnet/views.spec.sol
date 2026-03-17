// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IMetaHooks} from "src/interfaces/IMetaHooks.sol";
import {console} from "forge-std/console.sol";

contract VaultViewsTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_erc4626_basic_views() public {
        // Use the actual vault/strategy contract, not the adapter
        address asset = stakedLPStrategy.asset();
        assertEq(asset, underlyingAsset, "Vault underlying asset should be Curve LP token");

        uint8 decimals = stakedLPStrategy.decimals();
        assertEq(decimals, 18, "Vault decimals should be 18");

        string memory name = stakedLPStrategy.name();
        // Fix to reflect actual name based on DeployStrategy config (see BaseIntegrationTest)
        assertEq(name, "Staked LP Strategy ynRWAx-ynUSDx", "Vault name should match the expected name exactly");

        string memory symbol = stakedLPStrategy.symbol();
        // Fix to reflect actual symbol based on DeployStrategy config (see BaseIntegrationTest)
        assertEq(symbol, "sLP-ynRWAx-ynUSDx", "Vault symbol should match the expected symbol exactly");

        uint256 totalAssets = stakedLPStrategy.totalAssets();
        assertEq(totalAssets, 0, "Initial totalAssets should be 0");

        address alice = makeAddr("alice");
        uint256 maxDeposit = stakedLPStrategy.maxDeposit(alice);
        assertEq(maxDeposit, type(uint256).max, "maxDeposit should be max");

        uint256 maxMint = stakedLPStrategy.maxMint(alice);
        assertEq(maxMint, type(uint256).max, "maxMint should be max");

        uint256 maxWithdraw = stakedLPStrategy.maxWithdraw(alice);
        uint256 maxRedeem = stakedLPStrategy.maxRedeem(alice);

        assertEq(maxWithdraw, 0, "maxWithdraw for Alice should be 0 before deposit");
        assertEq(maxRedeem, 0, "maxRedeem for Alice should be 0 before deposit");

        // Get the assets array and assert its contents and length
        address[] memory assets = stakedLPStrategy.getAssets();
        assertEq(assets.length, 2, "Strategy should have 2 assets registered");
        assertEq(assets[0], underlyingAsset, "First asset should be underlyingAsset");
        assertEq(assets[1], targetVault, "Second asset should be targetVault");
    }

    function test_previewDeposit() public {
        address alice = makeAddr("alice");
        uint256 depositAmount = 10_000e6;
        deal(MC.USDC, alice, depositAmount);

        // Preview deposit: stakedLPStrategy.previewDeposit
        uint256 previewShares = stakedLPStrategy.previewDeposit(depositAmount);
        assertGt(previewShares, 0, "previewDeposit should return >0 shares for deposit");
    }

    function test_previewMint() public view {
        uint256 mintAmount = 100e18; // 100 shares

        // Preview mint: how much USDC needed to get certain shares?
        uint256 previewMintAssets = stakedLPStrategy.previewMint(mintAmount);
        assertGt(previewMintAssets, 0, "previewMint should return >0 assets");
    }

    function test_previewWithdraw() public {
        // Use realistic LP deposit workflow from the shared helper to ensure proper minting of LP tokens
        address alice = makeAddr("alice");
        uint256 depositAmount = 1_000e6;
        uint256 lpTokens = deposit_lp(alice, depositAmount);

        // Deposit LP tokens into the strategy for Alice
        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpTokens);
        stakedLPStrategy.deposit(lpTokens, alice);
        vm.stopPrank();

        // Preview withdraw: how many shares required to withdraw given assets?
        uint256 withdrawAmount = 1_000e6;
        uint256 previewWithdrawShares = stakedLPStrategy.previewWithdraw(withdrawAmount);
        assertGt(previewWithdrawShares, 0, "previewWithdraw returns shares required");
    }

    function test_previewRedeem() public {
        address alice = makeAddr("alice");
        uint256 depositAmount = 1_000e6;

        // Use helper for minting curve LP and depositing it to the strategy for Alice
        uint256 lpBalance = deposit_lp(alice, depositAmount);

        // Deposit LP tokens into the strategy for Alice
        vm.startPrank(alice);
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);
        stakedLPStrategy.deposit(lpBalance, alice);
        vm.stopPrank();

        // Preview redeem: how many assets returned for given shares?
        uint256 redeemAmount = 1e18;
        uint256 previewRedeemAssets = stakedLPStrategy.previewRedeem(redeemAmount);
        assertGt(previewRedeemAssets, 0, "previewRedeem returns USDC for shares");
    }

    function test_totalAssets_and_max_functions() public {
        address alice = makeAddr("alice");
        uint256 depositAmount = 10_000e6;
        deal(MC.USDC, alice, depositAmount);

        // Convert USDC to ynUSDx, then deposit into Curve LP for Alice
        vm.startPrank(alice);

        // Approve and deposit USDC to ynUSDx Vault
        IERC20(MC.USDC).approve(MC.YNUSDX, depositAmount);
        uint256 ynusdxBalance = IERC4626(MC.YNUSDX).deposit(depositAmount, alice);

        // Approve ynUSDx to Curve LP
        IERC20(MC.YNUSDX).approve(underlyingAsset, ynusdxBalance);

        // Provide ynUSDx as one-sided liquidity (all in amounts[1])
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = ynusdxBalance;
        ICurvePool(underlyingAsset).add_liquidity(amounts, 0);

        uint256 lpBalance = IERC20(underlyingAsset).balanceOf(alice);

        // Now deposit LP tokens into the strategy for Alice
        IERC20(underlyingAsset).approve(address(stakedLPStrategy), lpBalance);
        stakedLPStrategy.deposit(lpBalance, alice);

        vm.stopPrank();

        // Can check totalAssets and max functions
        uint256 totalAssets = stakedLPStrategy.totalAssets();
        assertGt(totalAssets, 0, "totalAssets should be >0");

        uint256 aliceMaxDeposit = stakedLPStrategy.maxDeposit(alice);
        uint256 aliceMaxMint = stakedLPStrategy.maxMint(alice);
        uint256 aliceMaxWithdraw = stakedLPStrategy.maxWithdraw(alice);
        uint256 aliceMaxRedeem = stakedLPStrategy.maxRedeem(alice);

        assertGt(aliceMaxDeposit, 0, "maxDeposit should be >0");
        assertGt(aliceMaxMint, 0, "maxMint should be >0");
        assertGt(aliceMaxWithdraw, 0, "maxWithdraw should be >0");
        assertGt(aliceMaxRedeem, 0, "maxRedeem should be >0");
    }

    function test_preview_withdraw_single_sided(uint256 depositAmount, uint256 withdrawLpAmount) public {
        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);

        address alice = makeAddr("alice");

        deal(MC.USDC, alice, depositAmount);

        uint256 lpBalance = deposit_lp(alice, depositAmount);

        withdrawLpAmount = bound(withdrawLpAmount, 1, lpBalance);

        stakedLPStrategy.approve(address(strategyAdapter), withdrawLpAmount);

        uint256 redeemableAmount = strategyAdapter.previewWithdrawSingleSided(withdrawLpAmount);

        // Preview withdrawal from Curve
        uint256 expectedRedeemableAmount = ICurvePool(underlyingAsset).calc_withdraw_one_coin(withdrawLpAmount, 1);

        assertEq(redeemableAmount, expectedRedeemableAmount, "Redeemable amount mismatch");
    }

    function test_hooks_is_metahooks() public view {
        // The "hooks" for this strategy should be set to metahooks address
        IMetaHooks metaHooks = IMetaHooks(address(stakedLPStrategy.hooks()));
        assertEq(metaHooks.name(), "MetaHooks", "Hooks name should be MetaHooks");

        IHooks[] memory hooks = metaHooks.getHooks();
        assertEq(hooks.length, 3, "Hooks length should be 3");
        assertEq(hooks[0].name(), "ERC4626WrapperHooks", "Hooks[0] name should be ERC4626WrapperHooks");
        assertEq(hooks[1].name(), "PerformanceFeeHooks", "Hooks[1] name should be PerformanceFeeHooks");
        assertEq(hooks[2].name(), "ProcessAccountingGuardHook", "Hooks[2] name should be ProcessAccountingGuardHook");
    }

    function test_hooks_has_correct_config() public view {
        IMetaHooks metaHooks = IMetaHooks(address(stakedLPStrategy.hooks()));
        IHooks[] memory hooks = metaHooks.getHooks();
        assertEq(hooks[0].getConfig().beforeDeposit, false, "Hooks[0] beforeDeposit should be false");
        assertEq(hooks[0].getConfig().afterDeposit, true, "Hooks[0] afterDeposit should be true");
        assertEq(hooks[0].getConfig().beforeMint, false, "Hooks[0] beforeMint should be false");
        assertEq(hooks[0].getConfig().afterMint, true, "Hooks[0] afterMint should be true");
        assertEq(hooks[0].getConfig().beforeRedeem, true, "Hooks[0] beforeRedeem should be true");
        assertEq(hooks[0].getConfig().beforeWithdraw, true, "Hooks[0] beforeWithdraw should be true");
    }
}
