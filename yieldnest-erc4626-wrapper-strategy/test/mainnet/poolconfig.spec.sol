// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {ICurveStableSwapFactoryNG} from "src/interfaces/ICurveStableSwapFactoryNG.sol";
import {console} from "forge-std/console.sol";
import {MockERC4626, ERC20} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract VaultBasicFunctionalityTest is BaseIntegrationTest {
    // Use alice as the liquidity provider and write a generic function for depositing to the pool

    address alice = address(0x1111);

    MockERC4626 public assetA;
    MockERC4626 public assetB;

    address baseAsset = MC.USDS;

    function setUp() public override {
        super.setUp();

        assetA = new MockERC4626(ERC20(baseAsset), "Mock USDC", "MUSDC");
        assetB = new MockERC4626(ERC20(baseAsset), "Mock USDC", "MUSDC");

        // Mint 20e6 USDC to bob, approve both assets, and deposit into both MockERC4626 vaults
        address bob = address(0x2222);

        uint256 totalAmount = 20 * 10 ** IERC20Metadata(baseAsset).decimals();
        deal(baseAsset, bob, totalAmount);

        vm.startPrank(bob);

        IERC20(baseAsset).approve(address(assetA), totalAmount / 2);
        IERC20(baseAsset).approve(address(assetB), totalAmount / 2);

        assetA.deposit(totalAmount / 2, bob);
        assetB.deposit(totalAmount / 2, bob);

        vm.stopPrank();
    }

    function test_create_pool() public {
        uint256 A = 120;
        uint256 fee = 3500000;
        uint256 offpegFeeMultiplier = 120000000000;
        uint256 ma_exp_time = 1010;

        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);
        assertNotEq(poolAddress, address(0));
    }

    function poolTotalAssetValue(address poolAddress) public view returns (uint256) {
        uint256[] memory balances = ICurvePool(poolAddress).get_balances();
        uint256 totalAssetValue = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            address asset = ICurvePool(poolAddress).coins(i);
            totalAssetValue += MockERC4626(asset).convertToAssets(balances[i]);
        }
        return totalAssetValue;
    }

    function valuePerShare(address poolAddress) public view returns (uint256) {
        uint256 totalAssetValue = poolTotalAssetValue(poolAddress);
        uint256 totalShares = IERC20(poolAddress).totalSupply();
        return totalAssetValue * 1e18 / totalShares;
    }

    function printPoolCoinBalances(address poolAddress) public view {
        console.log("pool coin balances:");
        console.log("assetA:", IERC20(address(assetA)).balanceOf(poolAddress));
        console.log("assetB:", IERC20(address(assetB)).balanceOf(poolAddress));
    }

    struct PoolStats {
        uint256 redeemableAmount;
        int256 assetBDelta;
        uint256 lpBalanceAfterRedeem;
        uint256 virtualPriceAfter;
        uint256 totalAssetValueAfter;
        uint256 valuePerShareAfter;
        uint256 aliceAssetBBalance;
        uint256 dy_0_1;
        uint256 dy_1_0;
    }

    function getPoolStats(
        address poolAddress,
        address depositor,
        uint256,
        /*withdrawAmount*/
        uint8 coinIndex
    ) public view returns (PoolStats memory) {
        PoolStats memory stats;

        // Just read pool/account stats (no state changes)
        uint256 balance = IERC20(ICurvePool(poolAddress).coins(coinIndex)).balanceOf(depositor);

        stats.redeemableAmount = 0; // Cannot preview redeemable amount without a view function; set to 0 as a placeholder
        stats.assetBDelta = 0; // Cannot simulate delta in pure view; set to 0 as a placeholder
        stats.lpBalanceAfterRedeem = IERC20(poolAddress).balanceOf(depositor);
        stats.virtualPriceAfter = ICurvePool(poolAddress).get_virtual_price();
        stats.totalAssetValueAfter = poolTotalAssetValue(poolAddress);
        stats.valuePerShareAfter = valuePerShare(poolAddress);
        stats.aliceAssetBBalance = balance;
        stats.dy_0_1 = ICurvePool(poolAddress).get_dy(0, 1, 1e18);
        stats.dy_1_0 = ICurvePool(poolAddress).get_dy(1, 0, 1e18);

        return stats;
    }

    function printPoolStats(PoolStats memory stats) public pure {
        console.log("Pool Stats:");
        // console.log("  redeemableAmount:", stats.redeemableAmount);
        // console.log("  assetBDelta:", stats.assetBDelta);
        // console.log("  lpBalanceAfterRedeem:", stats.lpBalanceAfterRedeem);
        console.log("  virtualPrice:", stats.virtualPriceAfter);
        // console.log("  totalAssetValue:", stats.totalAssetValueAfter);
        console.log("  valuePerShare:", stats.valuePerShareAfter);
        // console.log("  aliceAssetBBalance:", stats.aliceAssetBBalance);
        console.log("  dy_0_1:", stats.dy_0_1);
        console.log("  dy_1_0:", stats.dy_1_0);
    }

    function test_create_pool_withdraw_liquidity_one_coin() public {
        uint256 A = 120;
        uint256 fee = 3000000;
        uint256 offpegFeeMultiplier = 120000000000;
        uint256 ma_exp_time = 1010;

        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);
        assertNotEq(poolAddress, address(0));

        _depositToPool(poolAddress, alice, 1e18, 1e18);

        uint256 lpBalance = IERC20(poolAddress).balanceOf(alice);

        console.log("lpBalance:", lpBalance);

        // Log pool price before and after withdrawing liquidity
        PoolStats memory statsBeforeRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
        printPoolStats(statsBeforeRemovingLiquidity);

        uint256 amountToRemove = 1e18;

        vm.startPrank(alice);
        ICurvePool(poolAddress).remove_liquidity_one_coin(amountToRemove, 1, 0);
        vm.stopPrank();

        PoolStats memory statsAfterRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
        printPoolStats(statsAfterRemovingLiquidity);
        printPoolCoinBalances(poolAddress);
        {
            // Deposit 1e18 of assetB (after gaining it by depositing USDS)
            deal(address(assetB), alice, amountToRemove); // Give alice 1e18 assetB tokens directly
            vm.startPrank(alice);
            IERC20(address(assetB)).approve(poolAddress, amountToRemove);
            uint256[] memory depositAmounts = new uint256[](2);
            depositAmounts[0] = 0;
            depositAmounts[1] = amountToRemove;
            ICurvePool(poolAddress).add_liquidity(depositAmounts, 0);
            vm.stopPrank();
        }

        PoolStats memory statsAfterReAdd = getPoolStats(poolAddress, alice, 1e18, 1);
        printPoolStats(statsAfterReAdd);
        assertGt(
            statsAfterReAdd.virtualPriceAfter,
            statsAfterRemovingLiquidity.virtualPriceAfter,
            "Virtual price should increase after re-adding assetB"
        );

        printPoolCoinBalances(poolAddress);
    }

    function skip_test_create_pool_loop_withdraw_liquidity_one_coin() public {
        uint256 A = 120;
        uint256 fee = 3000000;
        uint256 offpegFeeMultiplier = 120000000000;
        uint256 ma_exp_time = 1010;

        runLoopWithParams(A, fee, offpegFeeMultiplier, ma_exp_time);
    }

    function skip_test_create_pool_A_50_offpeg_20_fee_1000000_loop_withdraw_liquidity_one_coin() public {
        uint256 A = 50;
        uint256 fee = 1000000;
        uint256 offpegFeeMultiplier = 120000000000;
        uint256 ma_exp_time = 1010;

        runLoopWithParams(A, fee, offpegFeeMultiplier, ma_exp_time);
    }

    function test_create_pool_A_20_offpeg_20_fee_1000000_loop_withdraw_liquidity_one_coin() public {
        uint256 A = 100; // A = 20
        uint256 fee = 0; // 10000000; // FEE = 0.1%
        uint256 offpegFeeMultiplier = 200000000000; // OFPEG = 20
        uint256 ma_exp_time = 1010;

        runLoopWithParams(A, fee, offpegFeeMultiplier, ma_exp_time);
    }

    struct RunSlippageTestResult {
        uint256 aFactor;
        uint256 fee;
        uint256 offpegFeeMultiplier;
        uint256 deltaAssetB;
        uint256 slippage;
        uint256 amountToRemove;
        uint256 amountReceived;
        uint256 assetAAmount;
        uint256 assetBAmount;
    }

    function writeResultsToJson(RunSlippageTestResult[] memory results, string memory filePath) internal {
        string memory json = "[";
        for (uint256 i = 0; i < results.length; i++) {
            json = string.concat(
                json,
                "{",
                '"aFactor":',
                vm.toString(results[i].aFactor),
                ",",
                '"fee":',
                vm.toString(results[i].fee),
                ",",
                '"offpegFeeMultiplier":',
                vm.toString(results[i].offpegFeeMultiplier),
                ",",
                '"deltaAssetB":',
                vm.toString(results[i].deltaAssetB),
                ",",
                '"slippage":',
                vm.toString(results[i].slippage),
                ",",
                '"amountToRemove":',
                vm.toString(results[i].amountToRemove),
                ",",
                '"amountReceived":',
                vm.toString(results[i].amountReceived),
                ",",
                '"assetAAmount":',
                vm.toString(results[i].assetAAmount),
                ",",
                '"assetBAmount":',
                vm.toString(results[i].assetBAmount),
                "}"
            );
            if (i < results.length - 1) {
                json = string.concat(json, ",");
            }
        }
        json = string.concat(json, "]");
        vm.writeFile(filePath, json);
    }

    function runSlippageTest(address poolAddress, uint256 amountToRemove)
        public
        returns (RunSlippageTestResult memory result)
    {
        uint256 beforeBalance = IERC20(address(assetB)).balanceOf(alice);
        vm.startPrank(alice);
        ICurvePool(poolAddress).remove_liquidity_one_coin(amountToRemove, 1, 0);
        vm.stopPrank();

        uint256 afterBalance = IERC20(address(assetB)).balanceOf(alice);

        uint256 delta = afterBalance - beforeBalance;
        console.log("delta:", delta);

        console.log("Post removal:");

        PoolStats memory stats = getPoolStats(poolAddress, alice, 1e18, 1);
        printPoolStats(stats);
        printPoolCoinBalances(poolAddress);

        {
            // INSERT_YOUR_CODE
            uint256 amountToSell = 0.001e18;
            deal(address(assetA), alice, amountToSell); // Give alice 0.1e18 assetA
            uint256 assetBBefore = IERC20(address(assetB)).balanceOf(alice);
            vm.startPrank(alice);
            IERC20(address(assetA)).approve(poolAddress, amountToSell);
            uint256 amountReceived = ICurvePool(poolAddress).exchange(0, 1, amountToSell, 0); // Sell assetA (index 0) for assetB (index 1)
            vm.stopPrank();
            uint256 assetBAfter = IERC20(address(assetB)).balanceOf(alice);
            uint256 deltaAssetB = assetBAfter - assetBBefore;

            console.log("amountReceived:", amountReceived);
            console.log("deltaAssetB:", deltaAssetB);

            assertEq(deltaAssetB, amountReceived);

            uint256 slippage = (amountToSell - amountReceived) * 1e18 / amountToSell;
            console.log("slippage:", slippage);

            result.slippage = slippage;
            result.deltaAssetB = deltaAssetB;
            result.amountToRemove = amountToRemove;
            result.amountReceived = amountReceived;
            result.assetAAmount = IERC20(address(assetA)).balanceOf(poolAddress);
            result.assetBAmount = IERC20(address(assetB)).balanceOf(poolAddress);
        }
    }

    function skip_test_swap_slippage() public {
        uint256 withdrawalSizeIncrements = 10;
        uint256 aFactorIncrements = 13;
        RunSlippageTestResult[] memory results =
            new RunSlippageTestResult[](withdrawalSizeIncrements * aFactorIncrements);

        uint256 baseSnap;

        uint256 index = 0;
        for (uint256 j = 0; j < aFactorIncrements; j++) {
            for (uint256 i = 0; i < withdrawalSizeIncrements; i++) {
                baseSnap = vm.snapshot();

                uint256 A = 20 + 10 * j * 2; // A = 20
                uint256 fee = 0; // 10000000; // FEE = 0.1%
                uint256 offpegFeeMultiplier = 200000000000; // OFPEG = 20
                uint256 ma_exp_time = 1010;

                address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);

                _depositToPool(poolAddress, alice, 1e18, 1e18);

                uint256 amountToRemove = 0.1e18 * (i + 1);

                RunSlippageTestResult memory result;
                result = runSlippageTest(poolAddress, amountToRemove);

                result.aFactor = A;
                result.fee = fee;
                result.offpegFeeMultiplier = offpegFeeMultiplier;
                results[index++] = result;

                vm.revertTo(baseSnap);
            }
        }

        console.log("results.length:", results.length);

        writeResultsToJson(results, "./test-results/slippage_results.json");
    }

    function runLoopWithParams(uint256 A, uint256 fee, uint256 offpegFeeMultiplier, uint256 ma_exp_time) public {
        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);
        assertNotEq(poolAddress, address(0));

        _depositToPool(poolAddress, alice, 1e18, 1e18);

        uint256 lpBalance = IERC20(poolAddress).balanceOf(alice);

        console.log("lpBalance:", lpBalance);

        PoolStats memory statsBeforeRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
        printPoolStats(statsBeforeRemovingLiquidity);

        for (uint256 i = 0; i < 1; i++) {
            console.log("Iteration:", i);

            uint256 amountToRemove = 0.6e18;

            uint256 beforeBalance = IERC20(address(assetB)).balanceOf(alice);
            vm.startPrank(alice);
            ICurvePool(poolAddress).remove_liquidity_one_coin(amountToRemove, 1, 0);
            vm.stopPrank();

            uint256 afterBalance = IERC20(address(assetB)).balanceOf(alice);

            uint256 delta = afterBalance - beforeBalance;
            console.log("delta:", delta);

            console.log("Post removal:");

            PoolStats memory stats = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(stats);
            printPoolCoinBalances(poolAddress);

            {
                // Deposit amountToRemove of assetB (after gaining it by depositing USDS)
                deal(address(assetB), alice, 1e18); // Give alice amountToRemove assetB tokens directly
                vm.startPrank(alice);
                IERC20(address(assetB)).approve(poolAddress, delta);
                uint256[] memory depositAmounts = new uint256[](2);
                depositAmounts[0] = 0;
                depositAmounts[1] = delta;
                ICurvePool(poolAddress).add_liquidity(depositAmounts, 0);
                vm.stopPrank();
            }

            console.log("Post re-add:");
            PoolStats memory statsAfterReAdd = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterReAdd);
            assertGe(
                statsAfterReAdd.virtualPriceAfter,
                stats.virtualPriceAfter,
                "Virtual price should increase after re-adding assetB"
            );

            uint256 increasePercentageAfterRemoval = (
                stats.valuePerShareAfter - statsBeforeRemovingLiquidity.valuePerShareAfter
            ) * 10000 / statsBeforeRemovingLiquidity.valuePerShareAfter;

            console.log("increasePercentageAfterRemoval:", _toPercentString(increasePercentageAfterRemoval));

            uint256 increasePercentageAfterReAdd = (
                statsAfterReAdd.valuePerShareAfter - statsBeforeRemovingLiquidity.valuePerShareAfter
            ) * 10000 / statsBeforeRemovingLiquidity.valuePerShareAfter;

            console.log("increasePercentageAfterReAdd:", _toPercentString(increasePercentageAfterReAdd));
            printPoolCoinBalances(poolAddress);
        }
    }

    function _toPercentString(uint256 basisPoints) internal pure returns (string memory) {
        return string(abi.encodePacked(vm.toString(basisPoints / 100), ".", vm.toString(basisPoints % 100), "%"));
    }

    function create_pool(uint256 A, uint256 fee, uint256 offpegFeeMultiplier, uint256 ma_exp_time)
        public
        returns (address)
    {
        address[] memory coins = new address[](2);
        coins[0] = address(assetA);
        coins[1] = address(assetB);

        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = 3;
        assetTypes[1] = 3;

        bytes4[] memory methodIds = new bytes4[](2);
        methodIds[0] = bytes4(0x00000000);
        methodIds[1] = bytes4(0x00000000);

        address[] memory oracles = new address[](2);
        oracles[0] = address(0x0000000000000000000000000000000000000000);
        oracles[1] = address(0x0000000000000000000000000000000000000000);

        address poolAddress = ICurveStableSwapFactoryNG(MC.CURVE_STABLE_SWAP_FACTORY_NG).deploy_plain_pool(
            "AA/AB-test-pool",
            "TynAB",
            coins,
            A,
            fee,
            offpegFeeMultiplier,
            ma_exp_time,
            0,
            assetTypes,
            methodIds,
            oracles
        );
        return poolAddress;
    }

    function _depositToPool(address poolAddress, address depositor, uint256 amount1, uint256 amount2) internal {
        // USDC and coin order: [ynRWAx, GHO]
        address firstAsset = ICurvePool(poolAddress).coins(0);
        address secondAsset = ICurvePool(poolAddress).coins(1);

        uint256 firstAssetShares;
        uint256 secondAssetShares;

        {
            deal(baseAsset, depositor, amount1);

            vm.startPrank(depositor);
            // Deposit amount1 to firstAsset using ERC4626, store returned shares
            IERC20(baseAsset).approve(address(firstAsset), amount1);
            firstAssetShares = IERC4626(firstAsset).deposit(amount1, depositor);
            vm.stopPrank();
        }

        {
            // Mint or allocate USDC to depositor, then allocate USDC to ynRWAx via test logic (assume a swap/mint simulation)
            deal(baseAsset, depositor, amount2);

            vm.startPrank(depositor);
            // Deposit amount2 to secondAsset using ERC4626, store returned shares
            IERC20(baseAsset).approve(address(secondAsset), amount2);
            secondAssetShares = IERC4626(secondAsset).deposit(amount2, depositor);
            vm.stopPrank();
        }

        // depositor approves the pool to spend her tokens
        vm.startPrank(depositor);
        IERC20(firstAsset).approve(poolAddress, firstAssetShares);
        IERC20(secondAsset).approve(poolAddress, secondAssetShares);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = firstAssetShares;
        amounts[1] = secondAssetShares;

        // Deposit them both at the same time to the pool
        ICurvePool(poolAddress).add_liquidity(amounts, 0);
        vm.stopPrank();
    }

    function test_A_50_offpeg_fee_multiplier_5() public {
        uint256 A = 50;
        uint256 offpegFeeMultiplier = 5e10; // 10 decimals
        uint256 fee = 3000000;
        uint256 ma_exp_time = 1010;

        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);

        _depositToPool(poolAddress, alice, 1e18, 1e18);
    }

    function test_create_pool__assetA_assetB_withdraw_liquidity_one_coin() public {
        uint256 A = 120;
        uint256 fee = 3000000;
        uint256 offpegFeeMultiplier = 120000000000;
        uint256 ma_exp_time = 1010;

        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);
        assertNotEq(poolAddress, address(0));

        {
            _depositToPool(poolAddress, alice, 1e18, 1e18);

            uint256 lpBalance = IERC20(poolAddress).balanceOf(alice);

            console.log("lpBalance:", lpBalance);

            // Log pool price before and after withdrawing liquidity
            PoolStats memory statsBeforeRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsBeforeRemovingLiquidity);

            vm.startPrank(alice);
            ICurvePool(poolAddress).remove_liquidity_one_coin(1e18, 1, 0);
            vm.stopPrank();

            PoolStats memory statsAfterRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterRemovingLiquidity);
            printPoolCoinBalances(poolAddress);
            {
                // Deposit 1e18 of assetB (after gaining it by depositing USDS)
                deal(address(assetB), alice, 1e18); // Give alice 1e18 assetB tokens directly
                vm.startPrank(alice);
                IERC20(address(assetB)).approve(poolAddress, 1e18);
                uint256[] memory depositAmounts = new uint256[](2);
                depositAmounts[0] = 0;
                depositAmounts[1] = 1e18;
                ICurvePool(poolAddress).add_liquidity(depositAmounts, 0);
                vm.stopPrank();
            }

            getPoolStats(poolAddress, alice, 1e18, 1);

            PoolStats memory statsAfterReAdd = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterReAdd);
            assertGt(
                statsAfterReAdd.virtualPriceAfter,
                statsAfterRemovingLiquidity.virtualPriceAfter,
                "Virtual price should increase after re-adding assetB"
            );

            printPoolCoinBalances(poolAddress);
        }

        {
            uint256 lpBalance = IERC20(poolAddress).balanceOf(alice);

            console.log("lpBalance:", lpBalance);

            // Log pool price before and after withdrawing liquidity
            PoolStats memory statsBeforeRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsBeforeRemovingLiquidity);

            console.log("Removing liquidity from assetA");
            vm.startPrank(alice);
            ICurvePool(poolAddress).remove_liquidity_one_coin(1e18, 0, 0);
            vm.stopPrank();

            PoolStats memory statsAfterRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterRemovingLiquidity);
            printPoolCoinBalances(poolAddress);
            {
                // Deposit 1e18 of assetA (after gaining it by depositing USDS)
                deal(address(assetA), alice, 1e18); // Give alice 1e18 assetB tokens directly
                vm.startPrank(alice);
                IERC20(address(assetA)).approve(poolAddress, 1e18);
                uint256[] memory depositAmounts = new uint256[](2);
                depositAmounts[0] = 1e18;
                depositAmounts[1] = 0;
                ICurvePool(poolAddress).add_liquidity(depositAmounts, 0);
                vm.stopPrank();
            }

            PoolStats memory statsAfterReAdd = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterReAdd);
            assertGt(
                statsAfterReAdd.virtualPriceAfter,
                statsAfterRemovingLiquidity.virtualPriceAfter,
                "Virtual price should increase after re-adding assetA"
            );

            printPoolCoinBalances(poolAddress);
        }
    }

    function deposit_to_assets_and_boost_rate(address poolAddress) public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 100e18;

        uint256 donationAmount1 = 10e18;
        uint256 donationAmount2 = 11e18;

        // USDC and coin order: [ynRWAx, GHO]
        address firstAsset = ICurvePool(poolAddress).coins(0);
        address secondAsset = ICurvePool(poolAddress).coins(1);

        uint256 firstAssetShares;
        uint256 secondAssetShares;

        {
            deal(baseAsset, alice, amount1);

            vm.startPrank(alice);
            // Deposit amount1 to firstAsset using ERC4626, store returned shares
            IERC20(baseAsset).approve(address(firstAsset), amount1);
            firstAssetShares = IERC4626(firstAsset).deposit(amount1, alice);
            vm.stopPrank();

            deal(baseAsset, alice, donationAmount1);
            vm.startPrank(alice);
            IERC20(baseAsset).transfer(address(firstAsset), donationAmount1);
            vm.stopPrank();
        }

        {
            // Mint or allocate USDC to alice, then allocate USDC to ynRWAx via test logic (assume a swap/mint simulation)
            deal(baseAsset, alice, amount2);

            vm.startPrank(alice);
            // Deposit amount2 to secondAsset using ERC4626, store returned shares
            IERC20(baseAsset).approve(address(secondAsset), amount2);
            secondAssetShares = IERC4626(secondAsset).deposit(amount2, alice);
            vm.stopPrank();

            deal(baseAsset, alice, donationAmount2);
            vm.startPrank(alice);
            IERC20(baseAsset).transfer(address(secondAsset), donationAmount2);
            vm.stopPrank();
        }
    }

    function test_redee_and_arb() public {
        uint256 A = 20; // A = 20
        uint256 fee = 10000000; // FEE = 0.1%
        uint256 offpegFeeMultiplier = 200000000000; // OFPEG = 20
        uint256 ma_exp_time = 1010;

        address poolAddress = create_pool(A, fee, offpegFeeMultiplier, ma_exp_time);
        assertNotEq(poolAddress, address(0));

        deposit_to_assets_and_boost_rate(poolAddress);

        {
            _depositToPool(poolAddress, alice, 1e18, 1e18);

            uint256 lpBalance = IERC20(poolAddress).balanceOf(alice);

            console.log("lpBalance:", lpBalance);

            // Log pool price before and after withdrawing liquidity
            PoolStats memory statsBeforeRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsBeforeRemovingLiquidity);

            vm.startPrank(alice);
            ICurvePool(poolAddress).remove_liquidity_one_coin(5e17, 1, 0);
            vm.stopPrank();

            PoolStats memory statsAfterRemovingLiquidity = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterRemovingLiquidity);
            printPoolCoinBalances(poolAddress);

            uint256 aliceLpBalanceBefore = IERC20(poolAddress).balanceOf(alice);
            {
                uint256 aliceLpValue = aliceLpBalanceBefore * statsAfterRemovingLiquidity.valuePerShareAfter / 1e18;
                console.log("aliceLpBalance:", aliceLpBalanceBefore);
                console.log("aliceLpValue (using valuePerShareAfter):", aliceLpValue);
            }

            uint256 assetBSharesReceived;
            {
                vm.startPrank(alice);
                uint256 redeemedAssetAAmount = ICurvePool(poolAddress).remove_liquidity_one_coin(1e17, 0, 0);
                vm.stopPrank();

                // Use redeemedAssetAAmount of assetA, redeem it for baseAsset and deposit that into assetB
                vm.startPrank(alice);
                uint256 baseAssetReceived = IERC4626(assetA).redeem(redeemedAssetAAmount, alice, alice);

                // Now, deposit the baseAsset received into assetB
                IERC20(baseAsset).approve(address(assetB), baseAssetReceived);
                assetBSharesReceived = IERC4626(assetB).deposit(baseAssetReceived, alice);
                vm.stopPrank();
            }
            {
                // Deposit 1e18 of assetB (after gaining it by depositing USDS)
                // deal(address(assetB), alice, 1e18); // Give alice 1e18 assetB tokens directly
                vm.startPrank(alice);
                IERC20(address(assetB)).approve(poolAddress, assetBSharesReceived);
                uint256[] memory depositAmounts = new uint256[](2);
                depositAmounts[0] = 0;
                depositAmounts[1] = assetBSharesReceived;
                ICurvePool(poolAddress).add_liquidity(depositAmounts, 0);
                vm.stopPrank();
            }
            PoolStats memory statsAfterReAdd = getPoolStats(poolAddress, alice, 1e18, 1);
            printPoolStats(statsAfterReAdd);
            assertGt(
                statsAfterReAdd.virtualPriceAfter,
                statsAfterRemovingLiquidity.virtualPriceAfter,
                "Virtual price should increase after re-adding assetB"
            );

            printPoolCoinBalances(poolAddress);

            {
                // Show the value of Alice's LP tokens using valuePerShareAfter
                uint256 aliceLpBalance = IERC20(poolAddress).balanceOf(alice);
                uint256 aliceLpValue = aliceLpBalance * statsAfterReAdd.valuePerShareAfter / 1e18;
                console.log("aliceLpBalance:", aliceLpBalance);
                console.log("aliceLpValue (using valuePerShareAfter):", aliceLpValue);
                assertGt(
                    aliceLpBalance, aliceLpBalanceBefore, "Alice's LP balance should increase after re-adding assetB"
                );
            }
        }
    }
}
