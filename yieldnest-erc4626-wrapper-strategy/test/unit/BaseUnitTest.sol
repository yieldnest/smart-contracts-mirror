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
import {MockERC4626} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";
import {ERC4626WrapperHooks} from "src/hooks/ERC4626WrapperHooks.sol";
import {SafeRules} from "lib/yieldnest-vault/script/rules/SafeRules.sol";
import {BaseRules} from "lib/yieldnest-vault/script/rules/BaseRules.sol";
import {IVault} from "lib/yieldnest-vault/src/interface/IVault.sol";

contract BaseUnitTest is Test, AssertUtils {
    ERC4626WrapperStrategy public stakedLPStrategy;

    address public ADMIN = makeAddr("admin");

    MockERC4626 public mockERC4626;
    MockERC20 public mockERC20;

    function setUp() public virtual {
        mockERC20 = new MockERC20("MockToken", "MTKN");
        mockERC4626 = new MockERC4626(mockERC20, "MockVault", "MVLT");
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(new ERC4626WrapperStrategy()), ADMIN, "");
        stakedLPStrategy = ERC4626WrapperStrategy(payable(address(proxy)));

        address provider = address(new Provider(address(mockERC4626), 10 ** 18));

        ERC4626WrapperStrategy.InitParams memory params = ERC4626WrapperStrategy.InitParams({
            admin: ADMIN,
            name: "Mock Vault Wrapper",
            symbol: "mvlt",
            decimals_: 18,
            alwaysComputeTotalAssets_: true,
            defaultAssetIndex_: 0,
            countNativeAsset_: false
        });
        stakedLPStrategy.initialize(params);

        vm.startPrank(ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.PAUSER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.UNPAUSER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.PROCESSOR_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.PROVIDER_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.ASSET_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.BUFFER_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.PROCESSOR_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.ALLOCATOR_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.HOOKS_MANAGER_ROLE(), ADMIN);
        stakedLPStrategy.grantRole(stakedLPStrategy.FEE_MANAGER_ROLE(), ADMIN);
        vm.stopPrank();

        {
            // Configure assets and provider
            address underlyingAsset = IERC4626(mockERC4626).asset();

            vm.startPrank(ADMIN);
            // depositable and withdrawable
            stakedLPStrategy.addAsset(underlyingAsset, 18, true, true);
            // not depositable and not withdrawable
            stakedLPStrategy.addAsset(address(mockERC4626), false, false);

            stakedLPStrategy.setProvider(address(provider));
            vm.stopPrank();
        }

        vm.startPrank(ADMIN);
        stakedLPStrategy.unpause();
        vm.stopPrank();

        ERC4626WrapperHooks hooks =
            new ERC4626WrapperHooks(address(stakedLPStrategy), address(stakedLPStrategy), address(mockERC4626));
        vm.startPrank(ADMIN);
        stakedLPStrategy.setHooks(address(hooks));
        stakedLPStrategy.grantRole(stakedLPStrategy.PROCESSOR_ROLE(), address(hooks));

        {
            SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](3);
            rules[0] = BaseRules.getDepositRule(address(mockERC4626), address(stakedLPStrategy));
            rules[1] = BaseRules.getWithdrawRule(address(mockERC4626), address(stakedLPStrategy));
            rules[2] = BaseRules.getApprovalRule(address(mockERC20), address(mockERC4626));
            SafeRules.setProcessorRules(IVault(address(stakedLPStrategy)), rules, true);
        }
        vm.stopPrank();
    }
}
