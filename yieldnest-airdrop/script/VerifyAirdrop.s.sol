// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Airdrop, UserAmount } from "src/Airdrop.sol";

import { ProxyAdmin } from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import { console } from "forge-std/console.sol";

import { BaseScript } from "script/BaseScript.s.sol";
import { ProxyUtils } from "script/ProxyUtils.sol";

// forge script script/VerifyAirdrop.s.sol:VerifyAirdrop -s "run(string)"
// script/inputs/season-one-eigen-holesky.json --rpc-url holesky
contract VerifyAirdrop is BaseScript {
    Deployment public deployment;

    // @dev Order of the struct fields matters, it should be alphabetical
    struct Deployment {
        address airdropImplementation;
        address airdropProxy;
        address deployer;
        uint256 initialSafeBalance;
        address owner;
        address proxyAdmin;
        address proxyAdminOwner;
        address rewardsSafe;
        address token;
        uint256 totalAmount;
    }

    error InvalidDeployment();

    function run(string memory _path) public {
        _loadInput(_path);
        deployment = _loadDeployment();
        _verify();
    }

    function _verify() internal view {
        console.log("Airdrop Deployer:", deployment.deployer);
        console.log("Airdrop Proxy:", deployment.airdropProxy);
        console.log("Airdrop Implementation:", deployment.airdropImplementation);
        console.log("Proxy Admin:", deployment.proxyAdmin);
        console.log("Owner:", deployment.owner);
        console.log("Proxy Admin Owner:", deployment.proxyAdminOwner);
        console.log("Rewards Safe:", deployment.rewardsSafe);
        console.log("Token:", deployment.token);
        console.log("Total Amount:", deployment.totalAmount);
        console.log("Initial Safe Balance:", deployment.initialSafeBalance);

        _verifyViewFunctions();

        _verifyProxyAdmin();

        _verifyTotalAmount();

        console.log("Deployment verified successfully");
    }

    function _verifyProxyAdmin() internal view {
        // Verify ProxyAdmin owner
        ProxyAdmin proxyAdmin = ProxyAdmin(deployment.proxyAdmin);

        if (address(ProxyUtils.getProxyAdmin(deployment.airdropProxy)) != deployment.proxyAdmin) {
            revert("ProxyAdmin address mismatch");
        }

        if (proxyAdmin.owner() != deployment.proxyAdminOwner) {
            console.log("Expected ProxyAdmin owner:", deployment.proxyAdminOwner);
            console.log("Actual ProxyAdmin owner:", proxyAdmin.owner());
            revert InvalidDeployment();
        }

        console.log("\u2705 ProxyAdmin owner verified successfully: ", proxyAdmin.owner());
    }

    function _verifyViewFunctions() internal view {
        Airdrop airdrop = Airdrop(deployment.airdropProxy);

        // Verify view functions
        if (airdrop.paused()) {
            revert("Airdrop is paused when it should not be");
        }
        console.log("\u2705 Airdrop is not paused");

        if (airdrop.owner() != data.airdropOwner) {
            console.log("Expected Airdrop owner:", data.airdropOwner);
            console.log("Actual Airdrop owner:", airdrop.owner());
            revert("Airdrop owner verification failed");
        }
        console.log("\u2705 Airdrop owner verified successfully: ", airdrop.owner());

        if (airdrop.safe() != rewardsSafe) {
            revert("Airdrop safe address verification failed");
        }
        console.log("\u2705 Airdrop safe address verified successfully: ", airdrop.safe());

        if (address(airdrop.token()) != token) {
            revert("Airdrop token address verification failed");
        }
        console.log("\u2705 Airdrop token address verified successfully: ", address(airdrop.token()));
    }

    function _verifyTotalAmount() internal view {
        Airdrop airdrop = Airdrop(deployment.airdropProxy);

        // Verify user amounts
        uint256 totalTokens = 0;
        for (uint256 i = 0; i < userAmounts.length; i++) {
            UserAmount memory userAmount = userAmounts[i];
            uint256 onChainAmount = airdrop.amounts(userAmount.user);
            if (onChainAmount != userAmount.amount) {
                console.log("Mismatch for user: ", userAmount.user);
                console.log("Expected amount: ", userAmount.amount);
                console.log("On-chain amount: ", onChainAmount);
                revert InvalidDeployment();
            }
            totalTokens += onChainAmount;
        }

        if (totalTokens != deployment.totalAmount) {
            console.log("Total tokens mismatch");
            console.log("Expected total tokens: ", deployment.totalAmount);
            console.log("Actual total tokens: ", totalTokens);
            revert InvalidDeployment();
        }
        console.log("\u2705 Total tokens verified successfully");
        console.log("Total tokens: ", totalTokens);
    }

    function _loadDeployment() internal view returns (Deployment memory d) {
        string memory json = vm.readFile(_getDeploymentFile());
        d = abi.decode(vm.parseJson(json), (Deployment));
        console.log("Loaded deployment from:", _getDeploymentFile());
    }
}
