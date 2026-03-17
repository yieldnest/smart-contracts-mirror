// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Airdrop, IAirdrop, UserAmount } from "src/Airdrop.sol";

import { Test } from "forge-std/Test.sol";
import { TransparentUpgradeableProxy } from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { OwnableUpgradeable } from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";

import { MockERC20 } from "test/mock/MockERC20.sol";

import { BatchUpdate } from "script/BatchUpdate.sol";

contract AirdropSampleDataTest is Test, BatchUpdate {
    Airdrop public airdropImplementation;
    Airdrop public airdrop;
    TransparentUpgradeableProxy public proxy;
    MockERC20 public token;

    address public proxyAdminOwner = makeAddr("proxyAdminOwner");
    address public owner = makeAddr("owner");
    address public safe = makeAddr("safe");

    UserAmount[] public sampleUserAmounts;
    uint256 public sampleTotalAmount = 0;

    uint256 public amount = 1 ether;

    function setUp() public {
        token = new MockERC20("Token", "TKN", 18);

        airdropImplementation = new Airdrop();

        UserAmount[] memory userAmounts = new UserAmount[](0);

        bytes memory initParams = abi.encodeWithSelector(
            Airdrop.initialize.selector, address(owner), address(safe), address(token), userAmounts
        );

        proxy = new TransparentUpgradeableProxy(address(airdropImplementation), proxyAdminOwner, initParams);

        airdrop = Airdrop(address(proxy));

        _loadSample();

        deal(address(token), safe, sampleTotalAmount);

        vm.prank(safe);
        token.approve(address(airdrop), sampleTotalAmount);
    }

    function _loadSample() internal {
        string memory path = string(abi.encodePacked(vm.projectRoot(), "/test/utils/sample.json"));
        string memory json = vm.readFile(path);

        bytes memory parsedUserAmount = vm.parseJson(json, ".userAmounts");
        UserAmount[] memory userAmounts = abi.decode(parsedUserAmount, (UserAmount[]));

        uint256 totalUserAmount;
        for (uint256 i; i < userAmounts.length; i++) {
            totalUserAmount += userAmounts[i].amount;
        }

        UserAmount memory tempUserAmount;
        for (uint256 i; i < userAmounts.length; i++) {
            if (userAmounts[i].amount == 0) {
                continue;
            }
            tempUserAmount.user = userAmounts[i].user;
            tempUserAmount.amount = Math.mulDiv(userAmounts[i].amount, sampleTotalAmount, totalUserAmount);

            sampleUserAmounts.push(tempUserAmount);
            sampleTotalAmount += tempUserAmount.amount;
        }

        assertEq(sampleUserAmounts.length > 0, true, "Sample User Amounts");
    }

    function testUpdateUserAmountsWithSampleData() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.prank(owner);
        airdrop.updateUserAmounts(sampleUserAmounts);

        for (uint256 i; i < sampleUserAmounts.length; i++) {
            assertEq(airdrop.amounts(sampleUserAmounts[i].user), sampleUserAmounts[i].amount);
        }
    }

    function testUpdateUserAmountsInBatches() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        uint256 batchSize = 200;

        vm.startPrank(owner);
        updateUserAmountsInBatches(airdrop, sampleUserAmounts, batchSize);
        vm.stopPrank();

        for (uint256 i; i < sampleUserAmounts.length; i++) {
            assertEq(airdrop.amounts(sampleUserAmounts[i].user), sampleUserAmounts[i].amount);
        }
    }

    function testClaimWithSampleData() public {
        vm.prank(owner);
        airdrop.pause();
        assertEq(airdrop.paused(), true);

        vm.prank(owner);
        airdrop.updateUserAmounts(sampleUserAmounts);

        vm.prank(owner);
        airdrop.unpause();
        assertEq(airdrop.paused(), false);

        uint256 numberOfUsers = sampleUserAmounts.length;
        if (numberOfUsers > 100) {
            numberOfUsers = 100;
        }

        uint256 claimedAmount;
        for (uint256 i; i < numberOfUsers; i++) {
            if (sampleUserAmounts[i].amount == 0) {
                continue;
            }

            uint256 beforeBalance = token.balanceOf(sampleUserAmounts[i].user);

            vm.prank(sampleUserAmounts[i].user);
            airdrop.claim(sampleUserAmounts[i].amount);

            uint256 afterBalance = token.balanceOf(sampleUserAmounts[i].user);
            assertEq(afterBalance - beforeBalance, sampleUserAmounts[i].amount);

            claimedAmount += sampleUserAmounts[i].amount;
        }

        assertEq(token.balanceOf(safe), sampleTotalAmount - claimedAmount, "safe Balance");
    }

    function testDeployWithSampleData() public {
        bytes memory initParams = abi.encodeWithSelector(
            Airdrop.initialize.selector, address(owner), address(safe), address(token), sampleUserAmounts
        );

        new TransparentUpgradeableProxy(address(airdropImplementation), proxyAdminOwner, initParams);
    }
}
