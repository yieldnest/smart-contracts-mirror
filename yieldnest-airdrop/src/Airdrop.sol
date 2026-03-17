// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import { OwnableUpgradeable } from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IAirdrop, UserAmount } from "./IAirdrop.sol";

/**
 * @title Airdrop
 * @dev A contract that manages token airdrops and allows users to claim tokens stored in a safe.
 */
contract Airdrop is IAirdrop, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Stores the claimable amounts for each user.
    mapping(address user => uint256 amount) public amounts;

    /// @notice Address of the safe that holds the tokens.
    address public safe;

    /// @notice The token being airdropped.
    IERC20 public token;

    /**
     * @dev Modifier to check if the user can claim the specified amount.
     * Reverts if the amount is zero or exceeds the claimable balance.
     * @param _amountToClaim The amount the user is trying to claim.
     */
    modifier whenAvailable(uint256 _amountToClaim) {
        if (_amountToClaim == 0 || _amountToClaim > amounts[msg.sender]) {
            revert NoAirdrop();
        }
        _;
    }

    /**
     * @dev Disables initializers to prevent contract from being reinitialized.
     */
    constructor() {
        _disableInitializers();
    }

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
        public
        initializer
    {
        __Pausable_init();
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        if (_safe == address(0) || _token == address(0)) {
            revert InvalidInit();
        }

        safe = _safe;
        token = IERC20(_token);

        _updateUserAmounts(_userAmounts);
    }

    /**
     * @notice Pauses the contract, preventing claims.
     * Can only be called by the owner.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing claims.
     * Can only be called by the owner.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }
    /**
     * @notice Updates user amounts for the airdrop. Only callable by the owner when the contract is paused.
     * @dev Note this function can be front-run by a claimant to claim before the amount is updated
     *      if amount is non-zero.
     * @param _userAmounts An array of updated user amounts.
     */

    function updateUserAmounts(UserAmount[] calldata _userAmounts) external onlyOwner whenPaused {
        _updateUserAmounts(_userAmounts);
    }

    /**
     * @dev Internal function to update user amount and recalculate claimable amounts.
     * @param _userAmounts An array of updated user amount.
     */
    function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
        for (uint256 i; i < _userAmounts.length;) {
            amounts[_userAmounts[i].user] = _userAmounts[i].amount;
            unchecked {
                i += 1;
            }
        }
    }

    /**
     * @notice Claims the specified amount of tokens from the airdrop.
     * @param _amountToClaim The amount of tokens to claim.
     */
    function claim(uint256 _amountToClaim)
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        whenAvailable(_amountToClaim)
    {
        amounts[msg.sender] -= _amountToClaim;
        token.safeTransferFrom(safe, msg.sender, _amountToClaim);
        emit Claimed(msg.sender, _amountToClaim);
    }
}
