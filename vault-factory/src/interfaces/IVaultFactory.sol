// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IVaultFactory {
    struct VaultParams {
        address admin;
        address processor;
        address pauser;
        address unpauser;
        address feeManager;
        address resolver;
        address baseAsset;
        string tokenName;
        string tokenSymbol;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint256 timelockDuration;
        uint256 minWithdrawalAmount;
        uint256 maxDataLength;
        uint256 bootstrapAmount;
        address bootstrapReceiver;
    }

    struct FlexStrategyParams {
        bool deployStrategy;
        address multisig;
        address offRampAddress;
        address accountingProcessor;
        uint256 targetApy;
        uint256 lowerBound;
        uint256 minRewardableAssets;
        string strategyName;
        string strategySymbol;
        string accountingTokenName;
        string accountingTokenSymbol;
    }

    struct CreatedVault {
        address vault;
        address timelock;
        address wrappedToken;
        address provider;
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
        address safeGuard;
        address flexStrategy;
        address accountingToken;
        address accountingModule;
        address rewardsSweeper;
    }

    struct WithdrawalSystem {
        address withdrawalRequest;
        address withdrawer;
        address bagFactory;
        address requestPolicy;
    }

    event VaultCreated(address indexed creator, address indexed vault, address indexed timelock, CreatedVault created);
    event WithdrawalSystemDeployed(address indexed vault, address indexed timelock, WithdrawalSystem withdrawalSystem);
    event NonceAdvanced(address indexed caller, address marker);

    error AssetDecimalsTooHigh(uint8 decimals);
    error BootstrapSharesMismatch(uint256 actualShares, uint256 expectedShares);
    error BootstrapAmountTooLow(uint256 amount, uint256 minimum);
    error MissingRegistryValue(bytes32 key);
    error ZeroAddress();

    function createVault(VaultParams calldata params, FlexStrategyParams calldata flexParams)
        external
        returns (CreatedVault memory created);

    function deployWithdrawalSystem(
        address vault,
        address timelock,
        address resolver,
        address pauser,
        uint256 minWithdrawalAmount,
        uint256 maxDataLength
    ) external returns (WithdrawalSystem memory withdrawals);

    function advanceNonce() external returns (address marker);
}
