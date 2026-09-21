// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {PactMerchantRegistry} from "../src/PactMerchantRegistry.sol";

/// @title PactMerchantRegistry unit tests.
contract PactMerchantRegistryTest is Test {
    PactMerchantRegistry internal registry;

    address internal owner = address(this);
    address internal stranger = makeAddr("stranger");
    address internal merchantWallet = makeAddr("merchant-wallet");

    bytes32 internal constant MERCHANT_ID = keccak256("acme-coffee");

    event MerchantRegistered(bytes32 indexed merchantId, address indexed wallet);
    event MerchantStatusChanged(bytes32 indexed merchantId, bool active);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        registry = new PactMerchantRegistry();
    }

    function test_RegisterMerchant_Success() public {
        vm.expectEmit(true, true, false, false, address(registry));
        emit MerchantRegistered(MERCHANT_ID, merchantWallet);

        registry.registerMerchant(MERCHANT_ID, merchantWallet);

        (address wallet, bool active) = registry.getMerchant(MERCHANT_ID);
        assertEq(wallet, merchantWallet);
        assertTrue(active);
        assertTrue(registry.isMerchantActive(MERCHANT_ID));
    }

    function test_Revert_ZeroMerchantAddress() public {
        vm.expectRevert(PactMerchantRegistry.ZeroAddress.selector);
        registry.registerMerchant(MERCHANT_ID, address(0));
    }

    function test_Revert_ZeroMerchantId() public {
        vm.expectRevert(PactMerchantRegistry.InvalidMerchantId.selector);
        registry.registerMerchant(bytes32(0), merchantWallet);
    }

    function test_Revert_DuplicateMerchantId() public {
        registry.registerMerchant(MERCHANT_ID, merchantWallet);

        vm.expectRevert(PactMerchantRegistry.DuplicateMerchant.selector);
        registry.registerMerchant(MERCHANT_ID, makeAddr("other-wallet"));
    }

    function test_GetMerchant_UnknownReturnsEmpty() public view {
        (address wallet, bool active) = registry.getMerchant(keccak256("ghost"));
        assertEq(wallet, address(0));
        assertFalse(active);
        assertFalse(registry.isMerchantActive(keccak256("ghost")));
    }

    function test_SetMerchantStatus_DeactivateAndReactivate() public {
        registry.registerMerchant(MERCHANT_ID, merchantWallet);

        vm.expectEmit(true, false, false, true, address(registry));
        emit MerchantStatusChanged(MERCHANT_ID, false);
        registry.setMerchantStatus(MERCHANT_ID, false);
        assertFalse(registry.isMerchantActive(MERCHANT_ID));

        vm.expectEmit(true, false, false, true, address(registry));
        emit MerchantStatusChanged(MERCHANT_ID, true);
        registry.setMerchantStatus(MERCHANT_ID, true);
        assertTrue(registry.isMerchantActive(MERCHANT_ID));

        // Wallet must be unchanged by status flips.
        (address wallet,) = registry.getMerchant(MERCHANT_ID);
        assertEq(wallet, merchantWallet);
    }

    function test_Revert_SetMerchantStatus_UnknownMerchant() public {
        vm.expectRevert(PactMerchantRegistry.UnknownMerchant.selector);
        registry.setMerchantStatus(keccak256("ghost"), false);
    }

    function test_Revert_Unauthorized_Register() public {
        vm.prank(stranger);
        vm.expectRevert(PactMerchantRegistry.NotOwner.selector);
        registry.registerMerchant(MERCHANT_ID, merchantWallet);
    }

    function test_Revert_Unauthorized_SetStatus() public {
        registry.registerMerchant(MERCHANT_ID, merchantWallet);

        vm.prank(stranger);
        vm.expectRevert(PactMerchantRegistry.NotOwner.selector);
        registry.setMerchantStatus(MERCHANT_ID, false);
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("new-owner");

        vm.expectEmit(true, true, false, false, address(registry));
        emit OwnershipTransferred(owner, newOwner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);

        // Old owner can no longer act; new owner can.
        vm.expectRevert(PactMerchantRegistry.NotOwner.selector);
        registry.registerMerchant(MERCHANT_ID, merchantWallet);

        vm.prank(newOwner);
        registry.registerMerchant(MERCHANT_ID, merchantWallet);
        assertTrue(registry.isMerchantActive(MERCHANT_ID));
    }

    function test_Revert_TransferOwnership_ToZeroAddress() public {
        vm.expectRevert(PactMerchantRegistry.ZeroAddress.selector);
        registry.transferOwnership(address(0));
    }

    function test_Revert_Unauthorized_TransferOwnership() public {
        vm.prank(stranger);
        vm.expectRevert(PactMerchantRegistry.NotOwner.selector);
        registry.transferOwnership(stranger);
    }
}
