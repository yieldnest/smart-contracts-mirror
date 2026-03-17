// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title WrappedToken
 * @dev A contract that wraps an underlying ERC20 token, allowing for decimal normalization
 * between different tokens. This is useful for integrating tokens with varying decimal
 * places into a unified system.
 */
contract WrappedToken is Initializable, ERC20Upgradeable {
    /**
     * @dev The underlying token couldn't be wrapped.
     */
    error ERC20InvalidUnderlying(address token);
    /**
     * @dev Emitted when `sender` deposits `amount` of underlying tokens,
     * minting `shares` of wrapped tokens to `receiver`.
     */

    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares);

    /**
     * @dev Emitted when `sender` withdraws `amount` of underlying tokens to `receiver` by burning `shares` of wrapped tokens from `owner`.
     */
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 amount, uint256 shares
    );

    /**
     * @dev Emitted when the allocator status is changed.
     */
    event AllocatorStatusChanged(bool hasAllocator);

    // Role for allocators who can manage token allocations
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the wrapped token with the underlying token and metadata.
     * @param underlyingToken The token to be wrapped
     * @param name The name of the wrapped token
     * @param symbol The symbol of the wrapped token
     * @param decimalsValue The number of decimals for the wrapped token
     * @param tokenDecimalsOffset The decimal offset between underlying and wrapped token
     */
    function initialize(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        uint8 tokenDecimalsOffset
    ) public virtual initializer {
        _initialize(underlyingToken, name, symbol, decimalsValue, tokenDecimalsOffset);
    }

    function _initialize(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        uint8 tokenDecimalsOffset
    ) internal {
        if (address(underlyingToken) == address(this)) {
            revert ERC20InvalidUnderlying(address(this));
        }

        __ERC20_init(name, symbol);

        TokenStorage storage ts = _getTokenStorage();
        ts.underlyingToken = address(underlyingToken);
        ts.decimals = decimalsValue;
        ts.decimalsOffset = tokenDecimalsOffset;
    }

    /**
     * @dev Deposits `amount` of the underlying token and mints wrapped tokens to `receiver`.
     * @param amount The amount of underlying tokens to deposit.
     * @param receiver The address that will receive the wrapped tokens.
     * @return The amount of wrapped tokens minted.
     */
    function deposit(uint256 amount, address receiver) public returns (uint256) {
        uint256 shares = convertToShares(amount);

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares);

        return shares;
    }

    /**
     * @dev Redeems `shares` of wrapped tokens and withdraws underlying tokens to `receiver`.
     * @param shares The amount of wrapped tokens to redeem.
     * @param receiver The address that will receive the underlying tokens.
     * @param owner The address whose wrapped tokens will be burned.
     * @return The amount of underlying tokens withdrawn.
     */
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        uint256 assets = convertToAssets(shares);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Converts an amount of underlying assets to wrapped token shares.
     * @param assets The amount of underlying assets to convert
     * @return The equivalent amount of wrapped token shares
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        TokenStorage storage ts = _getTokenStorage();
        return assets * (10 ** ts.decimalsOffset);
    }

    /**
     * @dev Converts an amount of wrapped token shares to underlying assets.
     * @param shares The amount of wrapped token shares to convert
     * @return The equivalent amount of underlying assets
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        TokenStorage storage ts = _getTokenStorage();
        return Math.mulDiv(shares, 1, 10 ** ts.decimalsOffset, Math.Rounding.Floor);
    }

    /**
     * @dev Returns the decimals offset used for scaling deposits and withdrawals.
     */
    function decimalsOffset() public view returns (uint8) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.decimalsOffset;
    }

    /**
     * @dev Returns the address of the underlying token.
     * @return The address of the underlying token.
     */
    function asset() public view returns (address) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.underlyingToken;
    }

    /**
     * @dev See {ERC20-decimals}.
     */
    function decimals() public view virtual override(ERC20Upgradeable) returns (uint8) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.decimals;
    }

    /// Views ///

    /**
     * @dev Returns the backing information of the wrapped token.
     * @return totalWrappedInUnderlying The total value of wrapped tokens in terms of the underlying token
     * @return actualUnderlying The actual balance of underlying tokens held by the contract
     */
    function backing() public view returns (uint256 totalWrappedInUnderlying, uint256 actualUnderlying) {
        totalWrappedInUnderlying = convertToAssets(totalSupply());
        actualUnderlying = IERC20(asset()).balanceOf(address(this));

        return (totalWrappedInUnderlying, actualUnderlying);
    }

    /// Storage ///

    struct TokenStorage {
        address underlyingToken;
        uint8 decimals;
        uint8 decimalsOffset;
    }

    // keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TokenStorageLocation = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00;

    function _getTokenStorage() internal pure returns (TokenStorage storage ts) {
        bytes32 position = TokenStorageLocation;
        assembly {
            ts.slot := position
        }
    }
}
