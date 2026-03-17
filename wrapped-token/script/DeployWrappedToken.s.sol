// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {WrappedToken} from "../src/WrappedToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyUtils} from "./ProxyUtils.sol";
import {Vm} from "forge-std/Vm.sol";

contract DeployWrappedToken is Script {
    WrappedToken public wrappedToken;

    // Global variables for deployment data
    address public underlyingAddress;
    string public wrappedName;
    address public proxyAdmin;
    WrappedToken public implementation;
    TransparentUpgradeableProxy public proxy;

    function _deployTimelockController(address proposer, address executor, address _admin, uint256 minDelay)
        internal
        virtual
        returns (TimelockController)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        return new TimelockController(minDelay, proposers, executors, _admin);
    }

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /**
     * @dev Prompts the user for an address input with a default value if empty.
     * @param prompt The message to display to the user.
     * @param defaultValue The default address to use if no input is provided.
     * @return The address entered by the user or the default value.
     */
    function promptAddressInput(string memory prompt, address defaultValue) public returns (address) {
        Vm vm = Vm(CHEATCODE_ADDRESS);

        // Prompt user for address
        string memory addressInput = vm.prompt(prompt);

        if (bytes(addressInput).length == 0) {
            // If no input, use default value
            return defaultValue;
        }

        // Parse the address input
        return vm.parseAddress(addressInput);
    }

    function run() public {
        // Prompt for underlying token address
        underlyingAddress = promptAddressInput("Enter the underlying token address:", address(0));

        // Prompt for proxy admin address
        proxyAdmin = promptAddressInput("Enter the proxy admin address (leave empty to use sender):", msg.sender);
        if (proxyAdmin == address(0)) {
            proxyAdmin = address(msg.sender);
        }

        // Get the token information
        IERC20 underlyingToken = IERC20(underlyingAddress);
        string memory underlyingName = ERC20(underlyingAddress).name();
        string memory underlyingSymbol = ERC20(underlyingAddress).symbol();
        uint8 underlyingDecimals = ERC20(underlyingAddress).decimals();

        // Create wrapped token name and symbol
        wrappedName = string(abi.encodePacked("Wrapped ", underlyingName));
        string memory wrappedSymbol = string(abi.encodePacked("W", underlyingSymbol));

        // Calculate the decimals offset (target 18 decimals for wrapped token)
        uint8 decimalsOffset = 18 - underlyingDecimals;

        console.log("Deploying Wrapped Token for:", underlyingName);
        console.log("Underlying Address:", underlyingAddress);
        console.log("Wrapped Name:", wrappedName);
        console.log("Wrapped Symbol:", wrappedSymbol);
        console.log("Decimals Offset:", decimalsOffset);

        vm.startBroadcast();

        // Deploy implementation
        implementation = new WrappedToken();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy proxy with empty initialization data
        proxy = new TransparentUpgradeableProxy(address(implementation), proxyAdmin, "");
        console.log("Proxy deployed at:", address(proxy));

        // Initialize the implementation through the proxy
        WrappedToken(address(proxy)).initialize(underlyingToken, wrappedName, wrappedSymbol, 18, decimalsOffset);
        console.log("Wrapped token initialized");

        vm.stopBroadcast();

        // Save deployment information
        _saveDeployment();

        console.log("Deployment completed successfully");
    }

    function _deploymentFilePath() internal virtual returns (string memory) {
        uint256 chainId = block.chainid;
        string memory sanitizedName = _sanitizeFileName(wrappedName);

        return string.concat(vm.projectRoot(), "/deployments/", sanitizedName, "-", vm.toString(chainId), ".json");
    }

    function _sanitizeFileName(string memory name) internal pure returns (string memory) {
        bytes memory nameBytes = bytes(name);
        bytes memory result = new bytes(nameBytes.length);
        uint256 resultLength = 0;

        for (uint256 i = 0; i < nameBytes.length; i++) {
            // Keep alphanumeric characters and replace spaces with underscores
            if (
                (nameBytes[i] >= 0x30 && nameBytes[i] <= 0x39) // 0-9
                    || (nameBytes[i] >= 0x41 && nameBytes[i] <= 0x5A) // A-Z
                    || (nameBytes[i] >= 0x61 && nameBytes[i] <= 0x7A)
            ) {
                // a-z
                result[resultLength++] = nameBytes[i];
            } else if (nameBytes[i] == 0x20) {
                // space
                result[resultLength++] = 0x5F; // underscore
            }
        }

        // Create a new bytes array with the correct length
        bytes memory trimmedResult = new bytes(resultLength);
        for (uint256 i = 0; i < resultLength; i++) {
            trimmedResult[i] = result[i];
        }

        return string(trimmedResult);
    }

    function _saveDeployment() internal virtual {
        string memory root = "";
        vm.serializeString(root, "name", wrappedName);
        vm.serializeAddress(root, "deployer", msg.sender);
        vm.serializeAddress(root, "admin", proxyAdmin);
        vm.serializeAddress(root, "underlyingToken", underlyingAddress);

        vm.serializeAddress(root, "wrappedToken-proxyAdmin", ProxyUtils.getProxyAdmin(address(proxy)));
        vm.serializeAddress(root, "wrappedToken-proxy", address(proxy));

        string memory jsonOutput = vm.serializeAddress(root, "wrappedToken-implementation", address(implementation));

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}
