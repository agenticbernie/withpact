// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

import {Script, console} from "forge-std/Script.sol";
import {PactMerchantRegistry} from "../src/PactMerchantRegistry.sol";

/// @title Deploy PactMerchantRegistry.
/// @notice Dry-run (simulation, no broadcast):
///           forge script script/DeployRegistry.s.sol --rpc-url arc_testnet
///         Live broadcast (ONLY with explicit approval, after verifying the simulation):
///           forge script script/DeployRegistry.s.sol --rpc-url arc_testnet --broadcast
/// @dev Required env: PRIVATE_KEY, DEPLOYER_ADDRESS.
contract DeployRegistry is Script {
    function run() external returns (PactMerchantRegistry registry) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(vm.addr(key) == deployer, "DeployRegistry: PRIVATE_KEY does not match DEPLOYER_ADDRESS");

        vm.startBroadcast(key);
        registry = new PactMerchantRegistry();
        vm.stopBroadcast();

        console.log("PactMerchantRegistry deployed at:", address(registry));
        console.log("deployer:", deployer);
        console.log("chainId:", block.chainid);
        console.log("owner:", registry.owner());
    }
}
