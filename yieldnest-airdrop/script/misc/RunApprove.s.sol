// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract RunApprove is Script {
    address public constant TOKEN = 0xD14b1321fc6617AB674C559B4F3aC1bc0E34Fb4A;
    address public constant SPENDER = 0x30cf5387e1D065ff9Aba766eba1e203B16aDE665;

    function run() public {
        vm.startBroadcast();

        IERC20 token = IERC20(TOKEN);
        token.approve(SPENDER, type(uint256).max);

        vm.stopBroadcast();
    }
}
