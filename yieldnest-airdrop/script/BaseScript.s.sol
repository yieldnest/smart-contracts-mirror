// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25 <0.9.0;

import { BaseData } from "./BaseData.s.sol";

import { console } from "forge-std/console.sol";
import { IERC20Metadata as IERC20 } from
    "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IntermediateUserAmount, UserAmount } from "../src/IAirdrop.sol";

contract BaseScript is BaseData {
    Data public data;
    uint256 public initialSafeBalance;

    address public token;
    address public rewardsSafe;
    UserAmount[] public userAmounts;

    uint256 public totalAmount;

    error ChainIdNotSupported(uint256 chainId);
    error InvalidInput();
    error NoAirdrop();

    function setUp() public override {
        super.setUp();

        if (!isSupportedChainId(block.chainid)) {
            revert ChainIdNotSupported(block.chainid);
        }

        data = getData(block.chainid);
    }

    function _loadInput(string memory _path) internal {
        string memory path = string(abi.encodePacked(vm.projectRoot(), "/", _path));
        string memory json = vm.readFile(path);

        token = vm.parseJsonAddress(json, ".token");
        rewardsSafe = vm.parseJsonAddress(json, ".rewardsSafe");

        bytes memory parsedUserAmount = vm.parseJson(json, ".userAmounts");
        IntermediateUserAmount[] memory intermediateUserAmounts =
            abi.decode(parsedUserAmount, (IntermediateUserAmount[]));
        UserAmount[] memory userAmount = new UserAmount[](intermediateUserAmounts.length);

        for (uint256 i; i < intermediateUserAmounts.length; i++) {
            UserAmount memory userAmountItem = UserAmount({
                user: intermediateUserAmounts[i].user,
                amount: vm.parseUint(intermediateUserAmounts[i].amount)
            });
            userAmount[i] = userAmountItem;
        }

        delete userAmounts;

        totalAmount = 0;

        for (uint256 i; i < userAmount.length; i++) {
            // had to parse the amounts like this because the parsed json was returning the wrong values
            address user = userAmount[i].user;
            uint256 amount = userAmount[i].amount;

            userAmounts.push(UserAmount({ user: user, amount: amount }));
            totalAmount += amount;
        }

        initialSafeBalance = IERC20(token).balanceOf(rewardsSafe);
        if (initialSafeBalance == 0) {
            revert NoAirdrop();
        }
        if (totalAmount > initialSafeBalance) {
            revert InvalidInput();
        }

        console.log("Initial safe balance: ", initialSafeBalance);
        console.log("Total amount: ", totalAmount);
        console.log("User amounts length: ", userAmounts.length);

        if (userAmounts.length == 0) {
            revert InvalidInput();
        }
    }

    function _getDeploymentFile() internal view virtual returns (string memory) {
        string memory symbol = IERC20(token).symbol();

        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", symbol, "-", vm.toString(block.chainid), ".json");
    }
}
