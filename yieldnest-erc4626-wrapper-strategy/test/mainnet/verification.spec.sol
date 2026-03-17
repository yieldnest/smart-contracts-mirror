// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IMetaHooks} from "src/interfaces/IMetaHooks.sol";
import {VerifyStrategy} from "script/VerifyStrategy.s.sol";
import {BaseScript} from "script/BaseScript.sol";
import {console} from "forge-std/console.sol";

contract VerificationTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_verification() public {
        VerifyStrategy verifyStrategy = new VerifyStrategy();
        verifyStrategy.setDeploymentParameters(
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
        verifyStrategy.setEnv(BaseScript.Env.TEST);
        verifyStrategy.run();
    }
}
