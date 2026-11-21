// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVault {
    function initialize(
        address admin,
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint64 baseWithdrawalFee_,
        bool countNativeAsset_,
        bool alwaysComputeTotalAssets_,
        uint256 defaultAssetIndex_
    ) external;

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function PROCESSOR_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function UNPAUSER_ROLE() external view returns (bytes32);
    function PROVIDER_MANAGER_ROLE() external view returns (bytes32);
    function BUFFER_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_MANAGER_ROLE() external view returns (bytes32);
    function PROCESSOR_MANAGER_ROLE() external view returns (bytes32);
    function HOOKS_MANAGER_ROLE() external view returns (bytes32);
    function FEE_MANAGER_ROLE() external view returns (bytes32);
    function ASSET_WITHDRAWER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;

    function addAsset(address asset, bool active) external;
    function setProvider(address provider) external;
    function setBuffer(address buffer) external;
    function unpause() external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}
