// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {PactMerchantRegistry, IPactMerchantRegistry} from "../src/PactMerchantRegistry.sol";
import {PactPaymentExecutor} from "../src/PactPaymentExecutor.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @title StubRegistry
/// @notice Dishonest-registry stand-in: reports an ACTIVE merchant with a zero
///         wallet, which the honest registry can never produce. Lets tests prove
///         the executor refuses to route funds to address(0).
contract StubRegistry is IPactMerchantRegistry {
    function getMerchant(bytes32) external pure returns (address wallet, bool active) {
        return (address(0), true);
    }

    function isMerchantActive(bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title PactPaymentExecutor unit tests.
contract PactPaymentExecutorTest is Test {
    PactMerchantRegistry internal registry;
    PactPaymentExecutor internal executor;
    MockUSDC internal usdc;

    address internal payer = makeAddr("payer");
    address internal merchantWallet = makeAddr("merchant-wallet");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant MERCHANT_ACTIVE = keccak256("active-merchant");
    bytes32 internal constant MERCHANT_INACTIVE = keccak256("inactive-merchant");
    bytes32 internal constant MERCHANT_UNKNOWN = keccak256("ghost-merchant");

    uint256 internal constant PAYER_FUNDS = 1_000_000_000; // 1000.000000 mUSDC
    uint256 internal constant PAYMENT_AMOUNT = 250_000_000; // 250.000000 mUSDC

    event PaymentExecuted(
        bytes32 indexed paymentId,
        bytes32 indexed merchantId,
        address indexed merchant,
        address payer,
        address token,
        uint256 amount,
        bytes32 purposeHash,
        uint256 timestamp
    );

    function setUp() public {
        registry = new PactMerchantRegistry();
        usdc = new MockUSDC();
        executor = new PactPaymentExecutor(address(registry), address(usdc));

        registry.registerMerchant(MERCHANT_ACTIVE, merchantWallet);
        registry.registerMerchant(MERCHANT_INACTIVE, makeAddr("inactive-wallet"));
        registry.setMerchantStatus(MERCHANT_INACTIVE, false);

        usdc.mint(payer, PAYER_FUNDS);
        vm.prank(payer);
        usdc.approve(address(executor), type(uint256).max);
    }

    // --- Valid payment ---

    function test_ExecutePayment_Success_ExactAmountAndEvent() public {
        bytes32 paymentId = keccak256("payment-1");
        bytes32 purposeHash = keccak256("order-123");

        uint256 payerBefore = usdc.balanceOf(payer);
        uint256 merchantBefore = usdc.balanceOf(merchantWallet);

        vm.expectEmit(true, true, true, true, address(executor));
        emit PaymentExecuted(
            paymentId,
            MERCHANT_ACTIVE,
            merchantWallet,
            payer,
            address(usdc),
            PAYMENT_AMOUNT,
            purposeHash,
            block.timestamp
        );

        vm.prank(payer);
        executor.executePayment(paymentId, MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, purposeHash);

        assertEq(usdc.balanceOf(merchantWallet), merchantBefore + PAYMENT_AMOUNT);
        assertEq(usdc.balanceOf(payer), payerBefore - PAYMENT_AMOUNT);
        assertTrue(executor.usedPaymentIds(paymentId));
        // Executor must never hold funds (pull model: payer -> merchant directly).
        assertEq(usdc.balanceOf(address(executor)), 0);
    }

    // --- Rejections ---

    function test_Revert_UnknownMerchant() public {
        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.UnknownMerchant.selector);
        executor.executePayment(keccak256("p"), MERCHANT_UNKNOWN, address(usdc), PAYMENT_AMOUNT, bytes32(0));
    }

    function test_Revert_InactiveMerchant() public {
        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.InactiveMerchant.selector);
        executor.executePayment(keccak256("p"), MERCHANT_INACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));

        // Failed payment leaves no trace: id stays unused and balances unchanged.
        assertFalse(executor.usedPaymentIds(keccak256("p")));
        assertEq(usdc.balanceOf(payer), PAYER_FUNDS);
    }

    function test_Revert_ZeroAmount() public {
        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.ZeroAmount.selector);
        executor.executePayment(keccak256("p"), MERCHANT_ACTIVE, address(usdc), 0, bytes32(0));
    }

    function test_Revert_ZeroPaymentId() public {
        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.InvalidPaymentId.selector);
        executor.executePayment(bytes32(0), MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));
    }

    function test_Revert_DuplicatePaymentId() public {
        bytes32 paymentId = keccak256("payment-dup");

        vm.prank(payer);
        executor.executePayment(paymentId, MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));

        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.DuplicatePaymentId.selector);
        executor.executePayment(paymentId, MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));

        // Exactly one payment went through.
        assertEq(usdc.balanceOf(merchantWallet), PAYMENT_AMOUNT);
    }

    function test_Revert_UnsupportedToken() public {
        MockUSDC other = new MockUSDC();
        other.mint(payer, PAYER_FUNDS);

        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.UnsupportedToken.selector);
        executor.executePayment(keccak256("p"), MERCHANT_ACTIVE, address(other), PAYMENT_AMOUNT, bytes32(0));
    }

    function test_Revert_ZeroRecipient_ViaDishonestRegistry() public {
        StubRegistry stub = new StubRegistry();
        PactPaymentExecutor evil = new PactPaymentExecutor(address(stub), address(usdc));

        vm.prank(payer);
        vm.expectRevert(PactPaymentExecutor.ZeroRecipient.selector);
        evil.executePayment(keccak256("p"), MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));
    }

    // --- Constructor validation ---

    function test_Revert_Constructor_ZeroRegistry() public {
        vm.expectRevert(PactPaymentExecutor.ZeroAddress.selector);
        new PactPaymentExecutor(address(0), address(usdc));
    }

    function test_Revert_Constructor_ZeroUsdc() public {
        vm.expectRevert(PactPaymentExecutor.ZeroAddress.selector);
        new PactPaymentExecutor(address(registry), address(0));
    }

    // --- Configuration immutability (no admin functions exist) ---

    function test_NoSilentReconfiguration() public {
        // The executor exposes no setters: any attempt to reconfigure must fail
        // at the dispatcher (no fallback function).
        (bool ok,) = address(executor).call(abi.encodeWithSignature("setUsdc(address)", stranger));
        assertFalse(ok);

        (ok,) = address(executor).call(abi.encodeWithSignature("setRegistry(address)", stranger));
        assertFalse(ok);

        (ok,) = address(executor).call(abi.encodeWithSignature("transferOwnership(address)", stranger));
        assertFalse(ok);

        // And the configured addresses are exactly what was deployed with.
        assertEq(address(executor.usdc()), address(usdc));
        assertEq(address(executor.registry()), address(registry));
    }

    // --- Failed-transfer consistency ---

    function test_RevertingTokenTransfer_RollsBackAndAllowsRetry() public {
        bytes32 paymentId = keccak256("payment-retry");
        usdc.setFailRevert(true);

        vm.prank(payer);
        vm.expectRevert(MockUSDC.TransferFailed.selector);
        executor.executePayment(paymentId, MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));

        // State is consistent after the failure: id not consumed, balances untouched.
        assertFalse(executor.usedPaymentIds(paymentId));
        assertEq(usdc.balanceOf(payer), PAYER_FUNDS);
        assertEq(usdc.balanceOf(merchantWallet), 0);

        // Retry after the token recovers succeeds with the same payment id.
        usdc.setFailRevert(false);
        vm.prank(payer);
        executor.executePayment(paymentId, MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));
        assertEq(usdc.balanceOf(merchantWallet), PAYMENT_AMOUNT);
    }

    function test_SilentFalseTokenTransfer_Reverts() public {
        usdc.setFailSilent(true);

        vm.prank(payer);
        vm.expectRevert();
        executor.executePayment(keccak256("p"), MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));

        assertFalse(executor.usedPaymentIds(keccak256("p")));
    }

    function test_Revert_InsufficientAllowance() public {
        address poorPayer = makeAddr("poor-payer");
        usdc.mint(poorPayer, PAYER_FUNDS);
        // No approval given.

        vm.prank(poorPayer);
        vm.expectRevert();
        executor.executePayment(keccak256("p"), MERCHANT_ACTIVE, address(usdc), PAYMENT_AMOUNT, bytes32(0));
    }
}
