// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseRoles} from "script/roles/BaseRoles.sol";
import {console} from "forge-std/console.sol";
import {SafeRules, IVault} from "@yieldnest-vault-script/rules/SafeRules.sol";
import {StrategyDeployer} from "script/StrategyDeployer.sol";
import {ERC4626WrapperStrategy} from "src/ERC4626WrapperStrategy.sol";
import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "@yieldnest-vault-script/ProxyUtils.sol";
import {IProvider} from "lib/yieldnest-vault/src/interface/IProvider.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";
import {Script} from "forge-std/Script.sol";
import {Provider} from "src/module/Provider.sol";
import {IHooksFactory} from "src/interfaces/IHooksFactory.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {IMetaHooks} from "src/interfaces/IMetaHooks.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IFeeHooks} from "lib/yieldnest-vault/src/interface/IFeeHooks.sol";
import {IProcessAccountingGuardHook} from "src/interfaces/IProcessAccountingGuardHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBaseStrategy} from "lib/yieldnest-vault/src/interface/IBaseStrategy.sol";
import {
    IActors as IVerifierActors,
    RolesVerification
} from "lib/yieldnest-vault/script/verification/RolesVerification.sol";
import {console} from "forge-std/console.sol";

// forge script VerifyStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account
// <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>
contract VerifyStrategy is BaseScript, Test {
    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    function run() public virtual {
        _setup();
        _loadDeployment(deploymentEnv);
        assertNotEq(msg.sender, deployer, "msg.sender should not be deploye as this is a verifier script.");
        verify();
    }

    function verify() public view {
        console.log("==============================================");
        console.log("=          VERIFYING STRATEGY SETUP         =");
        console.log("==============================================");
        console.log("Verifying strategy at:       ", address(strategy));
        console.log("Target vault:                ", address(targetVault));
        console.log("==============================================");

        // Verify metadata
        assertEq(strategy.name(), name, "strategy name is invalid");
        assertEq(strategy.symbol(), symbol_, "strategy symbol is invalid");
        assertEq(strategy.decimals(), decimals, "strategy decimals is invalid");
        assertEq(strategy.provider(), address(rateProvider), "strategy provider is invalid");

        // Check asset configuration
        require(strategy.asset() == baseAsset, "strategy base asset mismatch");
        require(strategy.getAssets().length == 2, "strategy should support 2 assets");
        require(strategy.getAssets()[1] == targetVault, "second asset should be targetVault");
        assertEq(strategy.countNativeAsset(), countNativeAsset, "countNativeAsset mismatch");
        assertEq(strategy.alwaysComputeTotalAssets(), alwaysComputeTotalAssets, "alwaysComputeTotalAssets mismatch");
        assertEq(strategy.paused(), false, "strategy should not be paused");
        assertEq(IBaseStrategy(address(strategy)).getHasAllocator(), false, "strategy should not have allocator");
        assertEq(strategy.baseWithdrawalFee(), baseWithdrawalFee, "baseWithdrawalFee mismatch");

        // Proxy/implementation checks
        {
            console.log("==============================================");
            console.log("=      VERIFYING PROXY CONFIGURATION        =");
            console.log("==============================================");

            address implementationAddr = ProxyUtils.getImplementation(address(strategy));
            address proxyAdminAddr = ProxyUtils.getProxyAdmin(address(strategy));
            assertEq(proxyAdminAddr, strategyProxyAdmin, "Strategy proxy admin address mismatch");
            console.log("\u2705 Strategy implementation:      ", implementationAddr);
            console.log("\u2705 Strategy proxy admin:         ", proxyAdminAddr);
        }

        // Print addresses for manual inspection
        console.log("Strategy address:", address(strategy));
        console.log("Target vault:", address(targetVault));
        console.log("Rate provider:", address(rateProvider));
        console.log("Deployer:", deployer);

        // Verify basic ERC4626 metadata
        string memory _name = strategy.name();
        string memory _symbol = strategy.symbol();
        uint8 _decimals = strategy.decimals();
        address _asset = strategy.asset();

        require(bytes(_name).length != 0, "Name should be set");
        require(bytes(_symbol).length != 0, "Symbol should be set");
        require(_decimals == decimals, "Decimals should be 18");

        // Verify asset addresses expected configuration
        address[] memory assets = strategy.getAssets();
        require(assets.length == 2, "Should have 2 assets");
        require(assets[0] == _asset, "First asset mismatch");
        require(assets[1] == address(targetVault), "Second asset should be targetVault");

        // Ensure strategy is set up to use the correct rate provider
        address actualRateProvider = strategy.provider();
        require(actualRateProvider == address(rateProvider), "Rate provider does not match deployment");

        {
            // verify roles and proxy configuration
            RolesVerification.verifyDefaultRoles(strategy, timelock, IVerifierActors(address(actors))); // timelock, admin, updater, etc.
            RolesVerification.verifyRole(
                strategy, actors.FEE_MANAGER(), strategy.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
            );

            {
                // Adapted for local variables and context in this script
                bool isProxyAdmin = ProxyUtils.getProxyAdmin(address(strategy)) == strategyProxyAdmin;
                console.log(isProxyAdmin ? "\u2705" : "\u274C", "Proxy admin is correct:", strategyProxyAdmin);
                assertTrue(isProxyAdmin, "Proxy admin is not correct");

                bool isProxyAdminOwner =
                    Ownable(ProxyUtils.getProxyAdmin(address(strategy))).owner() == address(timelock);
                console.log(isProxyAdminOwner ? "\u2705" : "\u274C", "Proxy admin owner is correct:", address(timelock));
                assertTrue(isProxyAdminOwner, "Proxy admin owner is not correct");
            }

            // verify timelock and temporary roles
            RolesVerification.verifyTimelockRoles(timelock, IVerifierActors(address(actors)), minDelay);
            RolesVerification.verifyTemporaryRoles(strategy, deployer);
        }

        verifyHooks();

        {
            console.log("==============================================");
            console.log("MANUAL VERIFICATION REQUIRED");
            console.log("==============================================");
            console.log("Verify total assets and vault rate are reasonable:");
            console.log("- Total assets should be the same as the previous total assets");
            console.log("- Vault rate should be the same as the previous vault rate (vault.convertToAssets(1e18)");
            console.log("==============================================");

            console.log("==============================================");
            console.log("TOTAL ASSETS AND VAULT RATE:");
            console.log("==============================================");

            uint256 totalAssets = strategy.totalAssets();
            console.log("Total assets:", totalAssets);

            // Print rate by converting 1e18 shares to assets
            uint256 oneShare = 1e18;
            uint256 assetAmount = strategy.convertToAssets(oneShare);
            console.log("Vault rate (1 share in assets):", assetAmount);
        }

        // Log success
        console.log("Strategy verification passed.");
    }

    function verifyHooks() public view {
        // The "hooks" for this strategy should be set to metahooks address
        IMetaHooks metaHooks = IMetaHooks(address(strategy.hooks()));
        assertEq(metaHooks.name(), "MetaHooks", "Hooks name should be MetaHooks");

        IHooks[] memory hooks = metaHooks.getHooks();
        assertEq(hooks.length, 3, "Hooks length should be 3");
        assertEq(hooks[0].name(), "ERC4626WrapperHooks", "Hooks[0] name should be ERC4626WrapperHooks");
        assertEq(hooks[1].name(), "PerformanceFeeHooks", "Hooks[1] name should be PerformanceFeeHooks");
        assertEq(hooks[2].name(), "ProcessAccountingGuardHook", "Hooks[2] name should be ProcessAccountingGuardHook");

        assertEq(hooks[0].getConfig().beforeDeposit, false, "Hooks[0] beforeDeposit should be false");
        assertEq(hooks[0].getConfig().afterDeposit, true, "Hooks[0] afterDeposit should be true");
        assertEq(hooks[0].getConfig().beforeMint, false, "Hooks[0] beforeMint should be false");
        assertEq(hooks[0].getConfig().afterMint, true, "Hooks[0] afterMint should be true");
        assertEq(hooks[0].getConfig().beforeRedeem, true, "Hooks[0] beforeRedeem should be true");
        assertEq(hooks[0].getConfig().beforeWithdraw, true, "Hooks[0] beforeWithdraw should be true");

        IProcessAccountingGuardHook processAccountingGuardHook = IProcessAccountingGuardHook(address(hooks[2]));
        assertEq(processAccountingGuardHook.owner(), actors.ADMIN(), "ProcessAccountingGuardHook owner should be ADMIN");
        assertEq(
            processAccountingGuardHook.maxTotalAssetsDecreaseRatio(),
            0.001 ether,
            "ProcessAccountingGuardHook maxTotalAssetsDecreaseRatio should be 0.001 ether"
        );
        assertEq(
            processAccountingGuardHook.maxTotalAssetsIncreaseRatio(),
            0.002 ether,
            "ProcessAccountingGuardHook maxTotalAssetsIncreaseRatio should be 0.002 ether"
        );
        assertEq(
            processAccountingGuardHook.maxTotalSupplyIncreaseRatio(),
            0 ether,
            "ProcessAccountingGuardHook maxTotalSupplyIncreaseRatio should be 0 ether"
        );
        assertEq(
            processAccountingGuardHook.expectedPerformanceFee(),
            0 ether,
            "ProcessAccountingGuardHook expectedPerformanceFee should be 0 ether"
        );

        IFeeHooks feeHooks = IFeeHooks(address(hooks[1]));
        assertEq(Ownable(address(feeHooks)).owner(), actors.ADMIN(), "FeeHooks owner should be ADMIN");
        assertEq(feeHooks.performanceFee(), 0 ether, "FeeHooks performanceFee should be 0 ether");
        assertEq(
            feeHooks.performanceFeeRecipient(),
            actors.FEE_RECEIVER(),
            "FeeHooks performanceFeeRecipient should be FEE_RECEIVER"
        );
    }
}
