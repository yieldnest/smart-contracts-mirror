// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {AssertUtils} from "lib/yieldnest-vault/test/utils/AssertUtils.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {StakeDaoRules} from "script/rules/StakeDaoRules.sol";
import {ERC20Rules} from "script/rules/ERC20Rules.sol";
import {SafeRules} from "@yieldnest-vault-script/rules/SafeRules.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";
import {IActors} from "lib/yieldnest-vault/script/Actors.sol";
import {MainnetActors} from "lib/yieldnest-vault/script/Actors.sol";

interface IGauge {
    function claim_rewards() external;
    function claim_rewards(address owner, address receiver) external;

    function claimable_tokens(address owner) external returns (uint256);
}

contract VaultBasicFunctionalityTest is Test, AssertUtils {
    address GAUGE = 0xb341f2d7e56524B52E3F7989A2E59366e1e5F18F;

    IActors public actors;

    ERC4626WrapperStrategy public strategy;

    address rewardsReceiver = address(0x1234567890123456789012345678901234567890);

    function setUp() public virtual {
        strategy = ERC4626WrapperStrategy(payable(MC.STAK));

        actors = new MainnetActors();

        vm.startPrank(actors.ADMIN());

        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), actors.ADMIN());

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        rules[0] = StakeDaoRules.getAccountantClaimRule(MC.STAKEDAO_ACCOUNTANT);
        rules[1] = ERC20Rules.getTransferRule(MC.CRV, rewardsReceiver);
        SafeRules.setProcessorRules(IVault(address(strategy)), rules, true);

        vm.stopPrank();
    }

    function test_claim_rewards() public {
        // Call the accountant claim through the processor (i.e., use process function)
        {
            address[] memory tokens = new address[](1); // for test: no actual tokens/bytes if not needed
            bytes[] memory data = new bytes[](1); // for test: no actual data if not needed
            tokens[0] = address(GAUGE);
            data[0] = "";

            vm.startPrank(actors.PROCESSOR());
            // Use the processor function matching BaseVault.sol (984-988)
            address[] memory targets = new address[](1);
            targets[0] = MC.STAKEDAO_ACCOUNTANT;
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            bytes[] memory dataArr = new bytes[](1);
            dataArr[0] = abi.encodeWithSelector(bytes4(keccak256("claim(address[],bytes[])")), tokens, data);
            IVault(address(strategy)).processor(targets, values, dataArr);
            vm.stopPrank();
        }

        // Record initial CRV balances of rewardsReceiver and vault
        uint256 initialCrvBalReceiver = IERC20(MC.CRV).balanceOf(rewardsReceiver);
        uint256 initialCrvBalVault = IERC20(MC.CRV).balanceOf(address(strategy));

        assertGt(initialCrvBalVault, 1e18, "Initial CRV balance of vault is greater than one");
        // Call processor to transfer CRV to rewardsReceiver
        {
            vm.startPrank(actors.PROCESSOR());

            address[] memory targets = new address[](1);
            targets[0] = MC.CRV;
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            bytes[] memory dataArr = new bytes[](1);
            // transfer all CRV held by vault to the rewardsReceiver
            uint256 vaultCrv = IERC20(MC.CRV).balanceOf(address(strategy));
            dataArr[0] =
                abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), rewardsReceiver, vaultCrv);
            IVault(address(strategy)).processor(targets, values, dataArr);

            vm.stopPrank();
        }

        // Verify that all CRV held by the vault has been transferred to rewardsReceiver
        uint256 finalCrvBalReceiver = IERC20(MC.CRV).balanceOf(rewardsReceiver);
        uint256 finalCrvBalVault = IERC20(MC.CRV).balanceOf(address(strategy));
        assertEq(
            finalCrvBalReceiver - initialCrvBalReceiver,
            initialCrvBalVault,
            "CRV not transferred properly: receiver did not get all vault CRV"
        );
        assertEq(finalCrvBalVault, 0, "CRV not transferred properly: vault CRV balance is not zero");
    }
}
