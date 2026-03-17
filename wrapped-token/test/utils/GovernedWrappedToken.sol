// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrappedToken} from "src/WrappedToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title GovernedWrappedToken
 * @dev An extension of WrappedToken that allows authorized allocators to transfer
 * underlying tokens out of the contract for management purposes.
 */
contract GovernedWrappedToken is WrappedToken, AccessControlUpgradeable {
    bool public hasAllocator;

    /**
     * @dev Error thrown when a zero address is provided where a valid address is required.
     */
    error ZeroAddress();

    /**
     * @dev Role for governors who can manage token allocations
     */
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /**
     * @dev Emitted when a governor transfers underlying tokens out of the contract.
     */
    event UnderlyingWithdrawn(address indexed allocator, address indexed recipient, uint256 amount);

    function initialize(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        uint8 tokenDecimalsOffset,
        address admin,
        bool _hasAllocator
    ) public initializer {
        super.initialize(underlyingToken, name, symbol, decimalsValue, tokenDecimalsOffset);
        __AccessControl_init();

        hasAllocator = _hasAllocator;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Transfers a specified amount of the underlying token to a recipient.
     * Can only be called by accounts with the governor role.
     * @param recipient The address that will receive the tokens
     * @param amount The amount of underlying tokens to transfer
     */
    function withdrawUnderlying(address recipient, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();

        // Transfer the tokens to the recipient
        SafeERC20.safeTransfer(IERC20(asset()), recipient, amount);

        emit UnderlyingWithdrawn(msg.sender, recipient, amount);
    }

    /// Admin ///

    /**
     * @dev Sets whether the contract has an allocator role enabled.
     * @param _hasAllocator True to enable the allocator role, false to disable it.
     * @notice Only callable by the admin role.
     */
    function setHasAllocator(bool _hasAllocator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        hasAllocator = _hasAllocator;

        emit AllocatorStatusChanged(_hasAllocator);
    }

    /**
     * @dev Modifier to restrict function access to accounts with the allocator role.
     * Reverts if the caller does not have the allocator role.
     */
    modifier onlyAllocator() {
        TokenStorage storage ts = _getTokenStorage();

        if (hasAllocator) {
            _checkRole(ALLOCATOR_ROLE);
        }
        _;
    }
}
