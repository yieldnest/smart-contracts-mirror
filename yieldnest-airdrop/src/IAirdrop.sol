// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title UserAmount
 * @dev Struct representing a user and their claimable token amount.
 * @dev Order of the struct is alphabetical to facilitate JSON parsing in the scripts.
 * @param amount The amount of tokens claimable by the user.
 * @param user The address of the user eligible for the airdrop.
 */
struct UserAmount {
    uint256 amount;
    address user;
}

struct IntermediateUserAmount {
    string amount;
    address user;
}

/**
 * @title IAirdrop
 * @dev Interface for Airdrop contract with methods to claim and restake tokens, as well as getter functions
 * for public variables.
 */
interface IAirdrop {
    /**
     * @notice Claim tokens from the airdrop.
     * @param _amountToClaim Amount of tokens to claim.
     */
    function claim(uint256 _amountToClaim) external;

    /**
     * @notice Initializes the airdrop contract with the provided parameters.
     * @param _owner The address of the owner.
     * @param _safe The address of the safe holding the tokens.
     * @param _token The address of the token being airdropped.
     * @param _userAmounts An array of user amounts for the airdrop.
     */
    function initialize(
        address _owner,
        address _safe,
        address _token,
        UserAmount[] calldata _userAmounts
    )
        external;

    /**
     * @notice Pauses the contract, preventing claims.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, allowing claims.
     */
    function unpause() external;

    /**
     * @notice Updates user amounts for the airdrop.
     * @param _userAmounts An array of user amounts for the airdrop.
     */
    function updateUserAmounts(UserAmount[] calldata _userAmounts) external;

    /**
     * @notice Returns the address of the safe holding the tokens.
     * @return The safe address.
     */
    function safe() external view returns (address);

    /**
     * @notice Returns the address of the token being airdropped.
     * @return The token address.
     */
    function token() external view returns (IERC20);

    /// @notice Emitted when a user claims tokens from the airdrop.
    /// @param user The address of the user claiming tokens.
    /// @param amount The amount of tokens claimed.
    event Claimed(address user, uint256 amount);

    /**
     * @notice Thrown when no airdrop exists for the user.
     */
    error NoAirdrop();

    /**
     * @notice Thrown when the airdrop data is invalid (e.g., token amounts or addresses are incorrect).
     */
    error InvalidAirdrop();

    /**
     * @notice Thrown when the contract initialization is invalid due to missing or incorrect parameters.
     */
    error InvalidInit();
}
