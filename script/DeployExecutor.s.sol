// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

import {Script, console} from "forge-std/Script.sol";
import {PactPaymentExecutor} from "../src/PactPaymentExecutor.sol";

/// @title Deploy PactPaymentExecutor.
/// @notice Dry-run (simulation, no broadcast):
///           forge script script/DeployExecutor.s.sol --rpc-url arc_testnet
///         Live broadcast (ONLY with explicit approval, after verifying the simulation):
///           forge script script/DeployExecutor.s.sol --rpc-url arc_testnet --broadcast
/// @dev Required env: PRIVATE_KEY, DEPLOYER_ADDRESS, REGISTRY_ADDRESS, USDC_ADDRESS.
contract DeployExecutor is Script {
    function run() external returns (PactPaymentExecutor executor) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(vm.addr(key) == deployer, "DeployExecutor: PRIVATE_KEY does not match DEPLOYER_ADDRESS");

        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        require(registryAddress != address(0), "DeployExecutor: REGISTRY_ADDRESS is zero");
        require(usdcAddress != address(0), "DeployExecutor: USDC_ADDRESS is zero");

        vm.startBroadcast(key);
        executor = new PactPaymentExecutor(registryAddress, usdcAddress);
        vm.stopBroadcast();

        console.log("PactPaymentExecutor deployed at:", address(executor));
        console.log("deployer:", deployer);
        console.log("chainId:", block.chainid);
        console.log("registry:", address(executor.registry()));
        console.log("usdc:", address(executor.usdc()));
    }
}
