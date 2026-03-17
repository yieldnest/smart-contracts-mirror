// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseUnitTest} from "test/unit/BaseUnitTest.sol";

contract DepositUnitTest is BaseUnitTest {
    address internal alice = address(0xA11CE);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_deposit() public {
        deal(address(mockERC20), alice, 1000000e18);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), 1000000e18);
        stakedLPStrategy.deposit(1000000e18, alice);
        assertEq(stakedLPStrategy.balanceOf(alice), 1000000e18);
        vm.stopPrank();
    }

    function test_mint() public {
        deal(address(mockERC20), alice, 1000000e18);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), 1000000e18);
        stakedLPStrategy.mint(1000000e18, alice);
        assertEq(stakedLPStrategy.balanceOf(alice), 1000000e18);
        vm.stopPrank();
    }

    function test_deposit_then_donate_to_erc4626_then_deposit_again() public {
        // First deposit
        deal(address(mockERC20), alice, 1000e18);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), 1000e18);
        stakedLPStrategy.deposit(1000e18, alice);
        uint256 sharesAfterFirst = stakedLPStrategy.balanceOf(alice);
        assertEq(sharesAfterFirst, 1000e18, "Shares after first deposit should equal deposit amount");
        vm.stopPrank();

        {
            // Donate to ERC4626 vault (simulate someone else sending funds) using an intermediary holder
            address intermediary = address(0xBEEF);
            deal(address(mockERC20), intermediary, 500e18);
            vm.startPrank(intermediary);
            mockERC20.transfer(address(mockERC4626), 500e18);
            vm.stopPrank();
        }

        {
            uint256 secondDepositAmount = 1000e18;
            // Second deposit
            uint256 assetsBefore = mockERC4626.totalAssets();
            deal(address(mockERC20), alice, secondDepositAmount);
            vm.startPrank(alice);
            mockERC20.approve(address(stakedLPStrategy), secondDepositAmount);
            stakedLPStrategy.deposit(secondDepositAmount, alice);
            vm.stopPrank();
            uint256 assetsAfter = mockERC4626.totalAssets();
            assertEq(
                assetsAfter,
                assetsBefore + secondDepositAmount,
                "Vault assets should increase by deposit amount after second deposit"
            );
        }
    }

    function test_mint_then_donate_to_erc4626_then_mint_again() public {
        // First mint
        deal(address(mockERC20), alice, 1000e18);
        vm.startPrank(alice);
        mockERC20.approve(address(stakedLPStrategy), 1000e18);
        stakedLPStrategy.mint(1000e18, alice);
        uint256 sharesAfterFirst = stakedLPStrategy.balanceOf(alice);
        assertEq(sharesAfterFirst, 1000e18, "Shares after first mint should equal minted shares");
        vm.stopPrank();

        {
            // Donate to ERC4626 vault (simulate someone else sending funds) using an intermediary holder
            address intermediary = address(0xBEEF);
            deal(address(mockERC20), intermediary, 500e18);
            vm.startPrank(intermediary);
            mockERC20.transfer(address(mockERC4626), 500e18);
            vm.stopPrank();
        }

        {
            uint256 secondMintAmount = 1000e18;
            // Calculate the amount of assets that need to be deposited to mint the requested shares
            uint256 secondMintShares = stakedLPStrategy.previewDeposit(secondMintAmount);

            uint256 assetsBefore = mockERC4626.totalAssets();
            deal(address(mockERC20), alice, secondMintAmount);
            vm.startPrank(alice);
            mockERC20.approve(address(stakedLPStrategy), secondMintAmount);
            stakedLPStrategy.mint(secondMintShares, alice);
            vm.stopPrank();
            uint256 assetsAfter = mockERC4626.totalAssets();
            assertApproxEqAbs(
                assetsAfter,
                assetsBefore + secondMintAmount,
                1,
                "Vault assets should increase by assets deposited for second mint"
            );
        }

        uint256 assetsPerShare = mockERC4626.convertToAssets(1e18);
        // After a 50% donation, with no rounding/fees, the assets per share should be greater than 1e18
        assertApproxEqAbs(assetsPerShare, 1.5e18, 1, "convertToAssets: rate should be greater than 1 after donation");
    }
}
