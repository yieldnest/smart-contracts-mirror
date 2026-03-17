// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VerifyStrategy} from "script/VerifyStrategy.s.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract VerifyYnRWAxynUSDxStrategy is VerifyStrategy {
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
                baseWithdrawalFee: 0.001e8 // 0.1%
            })
        );
        setEnv(Env.PROD);
        super.run();
    }
}
