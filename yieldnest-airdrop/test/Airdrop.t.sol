// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Airdrop } from "../src/Airdrop.sol";
import { IAirdrop, UserAmount } from "../src/IAirdrop.sol";

import { Test } from "forge-std/Test.sol";

import { ProxyAdmin } from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { OwnableUpgradeable } from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";

import { MockERC20 } from "test/mock/MockERC20.sol";

import { ProxyUtils } from "script/ProxyUtils.sol";

contract AirdropTest is Test {
    Airdrop public airdrop;
    Airdrop public airdropImplementation;
    MockERC20 public token;
    TransparentUpgradeableProxy public proxy;

    address public proxyAdminOwner = makeAddr("proxyAdminOwner");
    address public owner = makeAddr("owner");
    address public safe = makeAddr("safe");

    Vm.Wallet public stakerWallet;
    address public staker;

    uint256 internal constant INITIAL_BALANCE = 1e3 ether;
    uint256 public amount = 1 ether;

    function setUp() public {
        token = new MockERC20("Token", "TKN", 18);

        stakerWallet = vm.createWallet("staker");
        staker = stakerWallet.addr;

        airdropImplementation = new Airdrop();

        UserAmount[] memory userAmounts = new UserAmount[](1);
        userAmounts[0] = UserAmount({ user: staker, amount: amount });

        bytes memory initParams = abi.encodeWithSelector(
            Airdrop.initialize.selector, address(owner), address(safe), address(token), userAmounts
        );

        proxy = new TransparentUpgradeableProxy(address(airdropImplementation), proxyAdminOwner, initParams);

        airdrop = Airdrop(address(proxy));

        deal(address(token), address(safe), INITIAL_BALANCE);

        vm.prank(safe);
        token.approve(address(airdrop), INITIAL_BALANCE);
    }

    function testDefaults() public view {
        address proxyAdmin = ProxyUtils.getProxyAdmin(address(airdrop));
        ProxyAdmin proxyAdminContract = ProxyAdmin(proxyAdmin);

        assertEq(address(proxy), address(airdrop));
        assertEq(address(proxyAdminContract.owner()), proxyAdminOwner);
        assertEq(address(airdrop.safe()), address(safe));
        assertEq(address(airdrop.token()), address(token));
        assertEq(address(airdrop.owner()), owner);
        assertEq(airdrop.paused(), false);

        assertEq(airdrop.amounts(staker), amount);
    }

    function testInvalidInitialization() public {
        {
            bytes memory initParams = abi.encodeWithSelector(
                Airdrop.initialize.selector, address(0), address(safe), address(token), new UserAmount[](0)
            );

            bytes memory revertData =
                abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0));

            vm.expectRevert(revertData);
            new TransparentUpgradeableProxy(address(airdropImplementation), proxyAdminOwner, initParams);
        }

        {
            bytes memory initParams = abi.encodeWithSelector(
                Airdrop.initialize.selector, address(owner), address(0), address(token), new UserAmount[](0)
            );

            vm.expectRevert(IAirdrop.InvalidInit.selector);
            new TransparentUpgradeableProxy(address(airdropImplementation), proxyAdminOwner, initParams);
        }
    }

    function testPause() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);
    }

    function testPauseRevertsNotOwner() public {
        bytes memory revertData =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this));
        vm.expectRevert(revertData);
        airdrop.pause();
    }

    function testPauseRevertsAlreadyPaused() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(owner);
        airdrop.pause();
    }

    function testUnpause() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.prank(owner);
        airdrop.unpause();
        assertEq(airdrop.paused(), false);
    }

    function testUnpauseRevertsNotOwner() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        bytes memory revertData =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this));
        vm.expectRevert(revertData);
        airdrop.unpause();
    }

    function testUnpauseRevertsNotPaused() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        vm.prank(owner);
        airdrop.unpause();
    }

    function testClaim() public {
        vm.prank(staker);
        airdrop.claim(amount);
        assertEq(token.balanceOf(staker), amount);

        assertEq(token.balanceOf(safe), INITIAL_BALANCE - amount, "safe Balance");
    }

    function testClaimRevertsIfPaused() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(staker);
        airdrop.claim(amount);

        assertEq(token.balanceOf(staker), 0);
    }

    function testClaimRevertsIfAmountZero() public {
        vm.expectRevert(IAirdrop.NoAirdrop.selector);
        vm.prank(staker);
        airdrop.claim(0);

        assertEq(token.balanceOf(staker), 0);
    }

    function testClaimRevertsIfAmountExceeds() public {
        vm.expectRevert(IAirdrop.NoAirdrop.selector);
        vm.prank(staker);
        airdrop.claim(amount * 2);

        assertEq(token.balanceOf(staker), 0);
    }

    function testUpdateUserAmounts() public {
        UserAmount[] memory userAmounts = new UserAmount[](1);
        userAmounts[0] = UserAmount({ user: staker, amount: amount * 2 });

        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.prank(owner);
        airdrop.updateUserAmounts(userAmounts);

        assertEq(airdrop.amounts(staker), amount * 2);
    }

    function testUpdateUserAmountsRevertsNotOwner() public {
        UserAmount[] memory userAmounts = new UserAmount[](1);
        userAmounts[0] = UserAmount({ user: staker, amount: amount * 2 });

        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        bytes memory revertData =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this));
        vm.expectRevert(revertData);
        airdrop.updateUserAmounts(userAmounts);
    }

    function testUpdateUserAmountsRevertsIfNotPaused() public {
        UserAmount[] memory userAmounts = new UserAmount[](1);
        userAmounts[0] = UserAmount({ user: staker, amount: amount * 2 });

        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        vm.prank(owner);
        airdrop.updateUserAmounts(userAmounts);
    }

    function testClaimAmountAfterUpdateUserAmounts() public {
        UserAmount[] memory userAmounts = new UserAmount[](1);
        userAmounts[0] = UserAmount({ user: staker, amount: amount * 2 });

        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.prank(owner);
        airdrop.updateUserAmounts(userAmounts);

        vm.prank(owner);
        airdrop.unpause();
        assertEq(airdrop.paused(), false);

        vm.prank(staker);
        airdrop.claim(amount * 2);
        assertEq(token.balanceOf(staker), amount * 2);

        assertEq(token.balanceOf(safe), INITIAL_BALANCE - amount * 2, "safe Balance");
    }
}
