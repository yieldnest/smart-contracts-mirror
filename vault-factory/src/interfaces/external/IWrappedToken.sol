// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrappedToken {
    function initialize(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        uint8 tokenDecimalsOffset
    ) external;

    function asset() external view returns (address);
    function decimals() external view returns (uint8);
    function decimalsOffset() external view returns (uint8);
}
