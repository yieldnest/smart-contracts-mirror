// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.sol";

contract DepositUnitTest is BaseUnitTest {
    address internal alice = address(0xA11CE);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_deposit_and_remove_erc4626_asset() public {
        uint256 depositAmount = 1_000_000e18;
        deal(address(mockERC20), alice, depositAmount);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), depositAmount);
        stakedLPStrategy.deposit(depositAmount, alice);
        assertEq(stakedLPStrategy.balanceOf(alice), depositAmount);
        // Withdraw underlying for all assets via processor (hooks)

        // First, redeem all shares from the mockERC4626 vault into the strategy using the processor.
        // Figure out the number of shares the strategy holds in mockERC4626.
        uint256 vaultShares = mockERC4626.balanceOf(address(stakedLPStrategy));
        assertGt(vaultShares, 0, "Strategy should hold vault shares after deposit");

        // Prepare processor call to mockERC4626.withdraw to the strategy itself
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockERC4626);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(
            mockERC4626.withdraw.selector, vaultShares, address(stakedLPStrategy), address(stakedLPStrategy)
        );

        // Save totalAssets before processor call
        uint256 totalAssetsBefore = stakedLPStrategy.totalAssets();

        // Call processor (must be called by someone with PROCESSOR_ROLE)
        vm.stopPrank(); // End any current prank as alice.
        vm.startPrank(ADMIN);
        stakedLPStrategy.processor(targets, values, calldatas);
        vm.stopPrank();

        // The strategy should now hold all the underlying assets from mockERC4626.
        assertEq(mockERC20.balanceOf(address(stakedLPStrategy)), depositAmount, "Strategy should now hold all assets");
        assertEq(mockERC4626.balanceOf(address(stakedLPStrategy)), 0, "Strategy should have no vault shares left");

        // Check that totalAssets is preserved
        uint256 totalAssetsAfter = stakedLPStrategy.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets should be preserved after unwrapping");

        {
            // Now delete the mockERC4626 asset from the strategy
            uint256 mockERC4626AssetIndex = 1; // index 0 is the base asset (mockERC20), index 1 is mockERC4626
            vm.startPrank(ADMIN);
            stakedLPStrategy.deleteAsset(mockERC4626AssetIndex);
            vm.stopPrank();
            // After deleting, asset list length should decrease and mockERC4626 should not be in the list
            address[] memory assetList = stakedLPStrategy.getAssets();
            for (uint256 i = 0; i < assetList.length; i++) {
                require(assetList[i] != address(mockERC4626), "mockERC4626 should be deleted from asset list");
            }
        }

        // Assert maxWithdraw for alice is depositAmount
        assertEq(stakedLPStrategy.maxWithdraw(alice), depositAmount, "maxWithdraw for alice should be depositAmount");
    }
}
