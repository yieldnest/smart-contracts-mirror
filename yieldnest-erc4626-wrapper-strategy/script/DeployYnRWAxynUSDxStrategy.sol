// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {DeployStrategy} from "script/DeployStrategy.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract DeployYnRWAxynUSDxStrategy is DeployStrategy {
    function run() public override {
        setDeploymentParameters(
            DeploymentParameters({
                name: "STAK",
                symbol_: "STAK",
                decimals: 18,
                baseAsset: MC.CURVE_ynRWAx_ynUSDx_LP,
                targetVault: MC.STAKEDAO_CURVE_ynRWAx_ynUSDx_VAULT,
                skipTargetVault: false,
                alwaysComputeTotalAssets: false,
                countNativeAsset: false,
                baseWithdrawalFee: 1e5 // 0.1%
            })
        );
        setEnv(Env.PROD);
        super.run();
    }
}
