// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/yieldnest-vault/src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Provider} from "src/module/Provider.sol";
import {DeployStrategy} from "script/DeployStrategy.sol";
import {BaseScript} from "script/BaseScript.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {StrategyAdapter} from "test/helpers/StrategyAdapter.sol";
import {IVault, ViewUtils} from "lib/yieldnest-vault/test/utils/ViewUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IProcessAccountingGuardHook} from "src/interfaces/IProcessAccountingGuardHook.sol";

contract BaseIntegrationTest is Test, AssertUtils {
    ERC4626WrapperStrategy public stakedLPStrategy;
    DeployStrategy public deployment;
    StrategyAdapter public strategyAdapter;

    address underlyingAsset;
    address targetVault;

    address public ADMIN = makeAddr("admin");

    function setUp() public virtual {
        deployment = new DeployStrategy();

        underlyingAsset = MC.CURVE_ynRWAx_ynUSDx_LP;
        targetVault = MC.STAKEDAO_CURVE_ynRWAx_ynUSDx_VAULT;

        deployment.setDeploymentParameters(
            BaseScript.DeploymentParameters({
                name: "Staked LP Strategy ynRWAx-ynUSDx",
                symbol_: "sLP-ynRWAx-ynUSDx",
                decimals: 18,
                baseAsset: underlyingAsset,
                targetVault: targetVault,
                countNativeAsset: false,
                alwaysComputeTotalAssets: false,
                skipTargetVault: false,
                baseWithdrawalFee: 0
            })
        );
        deployment.setEnv(BaseScript.Env.TEST);
        deployment.run();

        stakedLPStrategy = ERC4626WrapperStrategy(deployment.strategy());

        // Deploy the StrategyAdapter as a proxy, then call initialize after
        strategyAdapter =
            StrategyAdapter(address(new TransparentUpgradeableProxy(address(new StrategyAdapter()), ADMIN, "")));
        strategyAdapter.initialize(address(stakedLPStrategy), 1); // Use the correct index if needed
    }

    function deposit_lp(address alice, uint256 depositAmount) public returns (uint256) {
        // Deal USDC to alice
        uint256 aliceAmount = depositAmount;
        deal(MC.USDC, alice, aliceAmount);

        // Split the depositAmount into two equal parts for YNRWAX and ynUSDx (50/50 for simplicity)
        uint256 halfAmount = aliceAmount / 2;

        // Addresses required
        address usdc = MC.USDC;
        address curveLp = underlyingAsset;

        // Use constants directly
        address ynrwax = MC.YNRWAX;
        address ynusdx = MC.YNUSDX;

        vm.startPrank(alice);

        // Approve and deposit half USDC into YNRWAX for Alice
        IERC20(usdc).approve(ynrwax, halfAmount);
        IERC4626(ynrwax).deposit(halfAmount, alice);

        // Approve and deposit half USDC into ynUSDx for Alice
        IERC20(usdc).approve(ynusdx, halfAmount);
        IERC4626(ynusdx).deposit(halfAmount, alice);

        // Get resulting token balances
        uint256 ynrwaxBal = IERC20(ynrwax).balanceOf(alice);
        uint256 ynusdxBal = IERC20(ynusdx).balanceOf(alice);

        // Approve LP to spend tokens
        IERC20(ynrwax).approve(curveLp, ynrwaxBal);
        IERC20(ynusdx).approve(curveLp, ynusdxBal);

        // Add as liquidity to the 2-coin pool [ynRWAx, ynUSDx]
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ynrwaxBal; // ynRWAx balance
        amounts[1] = ynusdxBal; // ynUSDx balance

        uint256 lpTokens = ICurvePool(curveLp).add_liquidity(amounts, 0);

        vm.stopPrank();

        return lpTokens;
    }

    function setMaxTotalAssetsIncreaseRatio(address vault, uint256 _maxTotalAssetsIncreaseRatio) internal {
        address guardHook = ViewUtils.getHooks(IVault(payable(vault)), "ProcessAccountingGuardHook");
        address owner = Ownable(guardHook).owner();
        vm.startPrank(owner);
        IProcessAccountingGuardHook(guardHook).setMaxTotalAssetsIncreaseRatio(_maxTotalAssetsIncreaseRatio);
        vm.stopPrank();
    }
}
