// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWrappedToken {
    function asset() external view returns (address);
    function deposit(uint256 amount, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}
