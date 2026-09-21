// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

import {Script, console} from "forge-std/Script.sol";
import {PactMerchantRegistry} from "../src/PactMerchantRegistry.sol";

/// @title Register a merchant on a deployed PactMerchantRegistry.
/// @notice Dry-run (simulation, no broadcast):
///           forge script script/RegisterMerchant.s.sol --rpc-url arc_testnet
///         Live broadcast (ONLY with explicit approval, after verifying the simulation):
///           forge script script/RegisterMerchant.s.sol --rpc-url arc_testnet --broadcast
/// @dev Required env: PRIVATE_KEY, DEPLOYER_ADDRESS (must be the registry owner),
///      REGISTRY_ADDRESS, MERCHANT_ID_STRING (non-empty), MERCHANT_WALLET (non-zero).
///      The merchant id is keccak256(MERCHANT_ID_STRING); it is logged for reuse.
contract RegisterMerchant is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(vm.addr(key) == deployer, "RegisterMerchant: PRIVATE_KEY does not match DEPLOYER_ADDRESS");

        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        require(registryAddress != address(0), "RegisterMerchant: REGISTRY_ADDRESS is zero");

        string memory idString = vm.envString("MERCHANT_ID_STRING");
        require(bytes(idString).length > 0, "RegisterMerchant: MERCHANT_ID_STRING is empty");

        address wallet = vm.envAddress("MERCHANT_WALLET");
        require(wallet != address(0), "RegisterMerchant: MERCHANT_WALLET is zero");

        bytes32 merchantId = keccak256(bytes(idString));
        PactMerchantRegistry registry = PactMerchantRegistry(registryAddress);

        vm.startBroadcast(key);
        registry.registerMerchant(merchantId, wallet);
        vm.stopBroadcast();

        console.log("registry:", registryAddress);
        console.log("merchant id string:", idString);
        console.logBytes32(merchantId);
        console.log("merchant wallet:", wallet);
        console.log("chainId:", block.chainid);
    }
}
