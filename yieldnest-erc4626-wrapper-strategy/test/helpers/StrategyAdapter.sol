// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {console} from "forge-std/console.sol";

contract StrategyAdapter is Initializable {
    using SafeERC20 for IERC20;

    event SingleSidedWithdraw(
        address indexed user,
        uint256 strategyShareAmount,
        address curveAsset,
        uint256 curveAssetIndex,
        uint256 assetRedeemed
    );

    error InsufficientCurveLPBalance(uint256 currentCurveLPBalance, uint256 curveLPAmount);
    error InsufficientRedeemedAmount(uint256 redeemedAmount, uint256 minOut);

    IERC4626 public strategy;
    int128 public curveAssetIndex;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address strategyAddress, int128 _curveAssetIndex) public initializer {
        strategy = IERC4626(payable(strategyAddress));
        curveAssetIndex = _curveAssetIndex;
    }

    function previewWithdrawSingleSided(uint256 curveLPAmount) public view returns (uint256 redeemableAmount) {
        // Get the curve pool address and instance
        ICurvePool pool = ICurvePool(strategy.asset());

        // Preview withdrawal from Curve
        redeemableAmount = pool.calc_withdraw_one_coin(curveLPAmount, curveAssetIndex);
    }

    function withdrawSingleSided(uint256 curveLPAmount, uint256 minOut) public {
        // withdraw the staked LP tokens approved by msg.sender to receiver = address(this)
        strategy.withdraw(curveLPAmount, address(this), msg.sender);

        // STEP 1: redeem the staked LP tokens single-sided
        ICurvePool pool = ICurvePool(strategy.asset());

        uint256 currentCurveLPBalance = IERC20(strategy.asset()).balanceOf(address(this));

        if (currentCurveLPBalance < curveLPAmount) {
            revert InsufficientCurveLPBalance(currentCurveLPBalance, curveLPAmount);
        }

        uint256 redeemedAmount = pool.remove_liquidity_one_coin(curveLPAmount, curveAssetIndex, minOut);

        if (redeemedAmount < minOut) {
            revert InsufficientRedeemedAmount(redeemedAmount, minOut);
        }

        address curveAsset = pool.coins(uint256(uint128(curveAssetIndex)));

        IERC20(curveAsset).safeTransfer(msg.sender, redeemedAmount);

        emit SingleSidedWithdraw(
            msg.sender, curveLPAmount, curveAsset, uint256(uint128(curveAssetIndex)), redeemedAmount
        );
    }
}
