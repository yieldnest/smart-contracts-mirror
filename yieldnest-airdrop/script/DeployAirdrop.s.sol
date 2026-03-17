// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Airdrop, UserAmount } from "src/Airdrop.sol";

import { ProxyAdmin } from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { console } from "forge-std/console.sol";
import { IERC20Metadata as IERC20 } from
    "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseScript } from "script/BaseScript.s.sol";
import { BatchUpdate } from "script/BatchUpdate.sol";
import { ProxyUtils } from "script/ProxyUtils.sol";

/**
 * source .env && forge script script/DeployAirdrop.s.sol:DeployAirdrop -s "run(string)"
 *   script/inputs/season-one-eigen-holesky.json --rpc-url $HOLESKY_RPC_URL --sender $DEPLOYER_ADDRESS --account
 *   $DEPLOYER_ACCOUNT_NAME --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract DeployAirdrop is BaseScript, BatchUpdate {
    Airdrop public airdrop;
    Airdrop public airdropImpl;
    ProxyAdmin public proxyAdmin;
    uint256 public constant BATCH_SIZE = 800;

    error InvalidDeployment();

    function run(string memory _path) public {
        _loadInput(_path);

        console.log("Token address: ", token);
        console.log("Token symbol: ", IERC20(token).symbol());
        console.log("Deployment file: ", _getDeploymentFile());

        _deploy();
        _verify();
        _save();
        console.log("Deployment complete");
    }

    function _deploy() internal {
        vm.startBroadcast();

        address deployer = msg.sender;
        console.log("Deployer address: ", deployer);

        airdropImpl = new Airdrop();

        console.log("Deployed Airdrop implementation: ", address(airdropImpl));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(airdropImpl), data.proxyAdminOwner, "");

        console.log("Deployed Airdrop proxy: ", address(proxy));

        airdrop = Airdrop(address(proxy));

        UserAmount[] memory _userAmounts = new UserAmount[](0);
        airdrop.initialize(deployer, rewardsSafe, token, _userAmounts);

        console.log("Initialized Airdrop");

        airdrop.pause();
        console.log("Paused Airdrop for updating user amounts");

        updateUserAmountsInBatches(airdrop, userAmounts, BATCH_SIZE);

        console.log("Updated user amounts");

        airdrop.unpause();
        console.log("Unpaused Airdrop");

        airdrop.transferOwnership(data.airdropOwner);

        console.log("Transferred ownership to", data.airdropOwner);

        vm.stopBroadcast();

        proxyAdmin = ProxyAdmin(ProxyUtils.getProxyAdmin(address(proxy)));
    }

    function _verify() internal view {
        if (proxyAdmin.owner() != data.proxyAdminOwner) {
            revert InvalidDeployment();
        }
        if (airdrop.owner() != data.airdropOwner) {
            revert InvalidDeployment();
        }
        if (airdrop.safe() != rewardsSafe) {
            revert InvalidDeployment();
        }
        if (address(airdrop.token()) != token) {
            revert InvalidDeployment();
        }
        if (airdrop.paused()) {
            revert InvalidDeployment();
        }
    }

    function _save() internal {
        console.log("Saving deployment");
        string memory json;
        vm.serializeAddress(json, "airdropImplementation", address(airdropImpl));
        vm.serializeAddress(json, "airdropProxy", address(airdrop));
        vm.serializeAddress(json, "owner", data.airdropOwner);
        vm.serializeAddress(json, "proxyAdmin", address(proxyAdmin));
        vm.serializeAddress(json, "proxyAdminOwner", data.proxyAdminOwner);
        vm.serializeAddress(json, "rewardsSafe", rewardsSafe);
        vm.serializeAddress(json, "token", token);
        vm.serializeUint(json, "totalAmount", totalAmount);
        vm.serializeUint(json, "initialSafeBalance", initialSafeBalance);
        string memory finalJson = vm.serializeAddress(json, "deployer", msg.sender);
        vm.writeJson(finalJson, _getDeploymentFile());
    }
}
