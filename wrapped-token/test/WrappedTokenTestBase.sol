// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {WrappedToken} from "../src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimalsValue) ERC20(name, symbol) {
        _decimals = decimalsValue;
        _mint(msg.sender, 100_000_000_000_000 * 10 ** _decimals);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

abstract contract WrappedTokenTestBase is Test {
    WrappedToken public wrappedToken;
    MockToken public mockToken;
    address public user = address(1);
    address public proxyOwner = address(1234567);

    uint256 public underlyingUnit;

    function underlyingDecimals() public pure virtual returns (uint8);

    function setUp() public {
        mockToken = new MockToken("Mock Token", "MTK", underlyingDecimals());

        underlyingUnit = 10 ** underlyingDecimals();

        // Deploy implementation
        WrappedToken implementation = new WrappedToken();

        // Deploy proxy with empty initialization data
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyOwner), "");

        // Initialize the implementation through the proxy
        WrappedToken(address(proxy)).initialize(
            IERC20(address(mockToken)), "Wrapped Mock Token", "WMTK", 18, 18 - mockToken.decimals()
        );

        // Set up the wrapped token interface
        wrappedToken = WrappedToken(address(proxy));

        // Give user some tokens
        mockToken.transfer(user, 100_000_000_000 * underlyingUnit);

        // Approve wrapped token to spend mock tokens
        vm.startPrank(user);
        mockToken.approve(address(wrappedToken), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_Deposit(uint256 depositAmount) public {
        // Bound the deposit amount to avoid overflows and zero deposits
        depositAmount = bound(depositAmount, 1, 1_000_000_000 * underlyingUnit);

        uint256 userInitialBalance = mockToken.balanceOf(user);

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();

        // Check user's mock token balance decreased
        assertEq(
            mockToken.balanceOf(user),
            userInitialBalance - depositAmount,
            "User's mock token balance should decrease by deposit amount"
        );

        // Check user received wrapped tokens
        assertEq(wrappedToken.balanceOf(user), sharesReceived, "User should receive correct amount of wrapped tokens");

        // Check wrapped token has the deposited tokens
        assertEq(
            mockToken.balanceOf(address(wrappedToken)),
            depositAmount,
            "Wrapped token contract should hold the deposited tokens"
        );
    }

    function testFuzz_Redeem(uint256 depositAmount) public {
        // Bound the deposit amount to avoid overflows and zero deposits
        depositAmount = bound(depositAmount, 1, 1_000_000_000 * underlyingUnit);

        // First deposit
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        // Then redeem
        uint256 userInitialBalance = mockToken.balanceOf(user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();

        // Check user's wrapped token balance decreased
        assertEq(
            wrappedToken.balanceOf(user), 0, "User's wrapped token balance should be zero after redeeming all shares"
        );

        // Check user received mock tokens back
        assertEq(
            mockToken.balanceOf(user),
            userInitialBalance + assetsReceived,
            "User should receive back the correct amount of underlying tokens"
        );

        // Check that assets received match the original deposit (accounting for potential rounding)
        assertEq(
            assetsReceived,
            depositAmount,
            "Assets received should be approximately equal to amount deposited (within 1 unit)"
        );
    }

    function testFuzz_RedeemWithPreciseDecimals(uint256 depositAmount, uint256 redeemFraction) public {
        // Bound the deposit amount to avoid overflows and zero deposits
        depositAmount = bound(depositAmount, 1 * underlyingUnit, 1_000_000_000 * underlyingUnit);

        // Bound the redeem fraction to be between 1 and 100 (we'll divide by 100 to get a percentage)
        redeemFraction = bound(redeemFraction, 1, 100);

        // Record initial balance before any operations
        uint256 userInitialBalance = mockToken.balanceOf(user);

        // Deposit tokens
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        // Calculate a partial amount to redeem (between 1% and 100%)
        uint256 sharesToRedeem = (sharesReceived * redeemFraction) / 100;

        // Ensure we're redeeming at least 1 share
        vm.assume(sharesToRedeem > 0);

        // Record balances before redemption
        uint256 userInitialWrappedBalance = wrappedToken.balanceOf(user);
        uint256 userInitialTokenBalance = mockToken.balanceOf(user);

        // Redeem the partial amount
        uint256 assetsReceived = wrappedToken.redeem(sharesToRedeem, user, user);
        vm.stopPrank();

        // Check wrapped token balance decreased by the correct amount
        assertEq(
            wrappedToken.balanceOf(user),
            userInitialWrappedBalance - sharesToRedeem,
            "User's wrapped token balance should decrease by the redeemed shares"
        );

        // Check underlying token balance increased
        assertEq(
            mockToken.balanceOf(user),
            userInitialTokenBalance + assetsReceived,
            "User should receive the correct amount of underlying tokens"
        );

        // Verify the conversion was done correctly
        uint256 expectedAssets = wrappedToken.convertToAssets(sharesToRedeem);
        assertEq(assetsReceived, expectedAssets, "Assets received should match the expected conversion");

        // Verify that the conversion from shares to assets handles decimals correctly
        // The expected assets should be approximately (depositAmount * redeemFraction / 100)
        uint256 expectedApproxAssets = (depositAmount * redeemFraction) / 100;
        assertApproxEqAbs(
            assetsReceived,
            expectedApproxAssets,
            1,
            "Assets received should be approximately equal to expected fraction of deposit (within 1 unit)"
        );

        // Verify that the sum of wrapped token value and user's mock token balance
        // is less than or equal to the initial balance (accounting for rounding)
        uint256 remainingWrappedValue = wrappedToken.balanceOf(user);
        uint256 currentMockBalance = mockToken.balanceOf(user);

        // Calculate the value of remaining wrapped tokens in terms of mock tokens
        uint256 remainingWrappedValueInMockTokens = wrappedToken.convertToAssets(remainingWrappedValue);

        // Calculate the total value the user has (current mock balance + equivalent value of wrapped tokens)
        uint256 totalUserValue = currentMockBalance + remainingWrappedValueInMockTokens;

        // Due to rounding down in the conversion, the total value should be at most 1 wei less than initial
        assertApproxEqAbs(
            totalUserValue,
            userInitialBalance,
            1,
            "Total user value (mock tokens + wrapped value) should be approximately equal to initial (within 1 unit)"
        );

        // Verify that the total user value is less than or equal to the initial balance
        // This is important because conversions can only round down, never up
        assertLe(
            totalUserValue,
            userInitialBalance,
            "Total user value should not exceed the initial balance due to rounding down in conversions"
        );
    }

    function testTransferAndRedeem() public {
        address recipient = address(0x123);
        uint256 depositAmount = 1_000_000 * underlyingUnit; // 1 million tokens with 6 decimals
        uint256 transferFraction = 40; // 40% of shares will be transferred

        // Setup: Give recipient approval to spend wrapped tokens
        vm.prank(recipient);
        wrappedToken.approve(address(this), type(uint256).max);

        // User deposits underlying tokens
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        // Calculate shares to transfer (40% of total shares)
        uint256 sharesToTransfer = (sharesReceived * transferFraction) / 100;

        // Transfer a portion of wrapped tokens to recipient
        wrappedToken.transfer(recipient, sharesToTransfer);
        vm.stopPrank();

        // User redeems their remaining shares
        vm.startPrank(user);
        uint256 userAssetsReceived = wrappedToken.redeem(wrappedToken.balanceOf(user), user, user);
        vm.stopPrank();

        // Recipient redeems their shares
        vm.startPrank(recipient);
        uint256 recipientAssetsReceived = wrappedToken.redeem(wrappedToken.balanceOf(recipient), recipient, recipient);
        vm.stopPrank();

        // Calculate total assets redeemed
        uint256 totalAssetsRedeemed = userAssetsReceived + recipientAssetsReceived;

        // Verify total redeemed is less than or equal to the deposit amount
        assertLe(
            totalAssetsRedeemed,
            depositAmount,
            "Total redeemed assets should not exceed the initial deposit due to rounding down"
        );

        // Verify total redeemed is approximately equal to deposit amount (within 1 wei)
        assertApproxEqAbs(
            totalAssetsRedeemed,
            depositAmount,
            1,
            "Total redeemed assets should be approximately equal to deposit amount (within 1 unit)"
        );

        // Verify that any remaining USDC (delta) is still in the wrapped token contract
        assertEq(
            mockToken.balanceOf(address(wrappedToken)),
            depositAmount - totalAssetsRedeemed,
            "Any remaining USDC delta should be held by the wrapped token contract"
        );
    }

    function testFuzz_ConversionRates(uint256 depositAmount) public {
        // Bound the deposit amount to something reasonable
        vm.assume(depositAmount > 0 && depositAmount <= 1_000_000_000 * underlyingUnit);

        // Check conversion rates before any deposits
        assertEq(
            wrappedToken.convertToShares(underlyingUnit),
            1e18,
            "1 unit of assets should convert to 1e18 shares (12 decimal places difference)"
        );
        assertEq(
            wrappedToken.convertToAssets(1e18),
            underlyingUnit,
            "1e18 shares should convert to 1 unit of assets (12 decimal places difference)"
        );

        // Make a deposit
        vm.startPrank(user);
        wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();

        // Conversion rates should still be 1:1 regardless of deposit amount
        assertEq(
            wrappedToken.convertToShares(underlyingUnit), 1e18, "Conversion rate should remain stable after deposit"
        );
        assertEq(
            wrappedToken.convertToAssets(1e18), underlyingUnit, "Conversion rate should remain stable after deposit"
        );
    }

    function testFuzz_DepositRedeem(uint256 amount) public {
        // Bound the amount to something reasonable
        vm.assume(amount > 0 && amount <= 100_000_000 * underlyingUnit);

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(amount, user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();

        // Verify that the assets received are less than or equal to the amount deposited
        // This is important because in some cases there might be rounding down when converting
        // shares back to assets, but we should never get more assets than we put in
        assertLe(assetsReceived, amount, "Assets received should not exceed the amount deposited");

        // Should get back the same amount (minus potential rounding)
        assertApproxEqAbs(
            assetsReceived,
            amount,
            1,
            "Assets received should be approximately equal to amount deposited (within 1 unit)"
        );

        // Verify that the assets received are less than or equal to the amount deposited
        // This is a duplicate check to ensure we never receive more assets than deposited
        assertLe(assetsReceived, amount, "Assets received should never exceed the amount deposited");
    }
}
