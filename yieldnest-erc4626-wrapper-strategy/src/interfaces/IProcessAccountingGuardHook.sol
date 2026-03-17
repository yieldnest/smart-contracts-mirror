// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IProcessAccountingGuardHook {
    function setMaxTotalAssetsDecreaseRatio(uint256 _maxTotalAssetsDecreaseRatio) external;
    function setMaxTotalAssetsIncreaseRatio(uint256 _maxTotalAssetsIncreaseRatio) external;

    /// @notice The owner controls configuration settings
    function owner() external view returns (address);

    /// @notice The maximum total assets decrease ratio during processAccounting()
    function maxTotalAssetsDecreaseRatio() external view returns (uint256);

    /// @notice The maximum total assets increase ratio during processAccounting()
    function maxTotalAssetsIncreaseRatio() external view returns (uint256);

    /// @notice The maximum total supply increase ratio during processAccounting()
    function maxTotalSupplyIncreaseRatio() external view returns (uint256);

    /// @notice The expected performance fee
    function expectedPerformanceFee() external view returns (uint256);
}
