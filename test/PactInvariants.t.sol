// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {PactMerchantRegistry} from "../src/PactMerchantRegistry.sol";
import {PactPaymentExecutor} from "../src/PactPaymentExecutor.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @title PactHandler
/// @notice Invariant-test actor: randomly registers merchants, flips statuses,
///         pays active merchants, and replays old payment ids (which must fail).
/// @dev This contract owns the registry (ownership transferred in setUp) and is
///      the sole payer and sole minter, so all fund flows are fully tracked.
contract PactHandler is Test {
    MockUSDC internal usdc;
    PactMerchantRegistry internal registry;
    PactPaymentExecutor internal executor;

    bytes32[] internal merchantIds;
    mapping(bytes32 => address) internal merchantWallet;
    mapping(address => uint256) internal expectedReceived;
    mapping(address => bool) internal walletUsed;

    uint256 internal paymentNonce;
    uint256 internal merchantNonce = 3; // 0..2 seeded in setUp
    uint256 internal mintedTotal;

    bytes32 internal lastPaymentId;
    bytes32 internal lastMerchantId;
    uint256 internal lastAmount;
    bytes32 internal lastPurposeHash;
    bool internal hasLastPayment;

    uint256 internal constant MAX_TRACKED_MERCHANTS = 10;

    constructor(MockUSDC usdc_, PactMerchantRegistry registry_, PactPaymentExecutor executor_) {
        usdc = usdc_;
        registry = registry_;
        executor = executor_;
        usdc.approve(address(executor), type(uint256).max);
    }

    function seedMerchant(bytes32 merchantId, address wallet) external {
        // Seeding is a setUp-only helper, never a fuzz entry point (see
        // targetSelector below). Guard anyway: the handler, executor, token,
        // and registry must never be merchant wallets or ghost accounting breaks.
        require(wallet != address(0));
        require(wallet != address(this));
        require(wallet != address(executor));
        require(wallet != address(usdc));
        require(wallet != address(registry));
        require(!walletUsed[wallet]);
        walletUsed[wallet] = true;
        merchantIds.push(merchantId);
        merchantWallet[merchantId] = wallet;
        registry.registerMerchant(merchantId, wallet);
    }

    function fund(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000_000_000);
        usdc.mint(address(this), amount);
        mintedTotal += amount;
    }

    function pay(uint256 merchantSeed, uint256 amountSeed, bytes32 purposeHash) external {
        if (merchantIds.length == 0) return;
        bytes32 merchantId = merchantIds[merchantSeed % merchantIds.length];
        address wallet = merchantWallet[merchantId];

        uint256 balance = usdc.balanceOf(address(this));
        if (balance == 0) {
            usdc.mint(address(this), 1_000_000_000);
            mintedTotal += 1_000_000_000;
            balance = 1_000_000_000;
        }
        uint256 amount = bound(amountSeed, 1, balance);

        paymentNonce += 1;
        bytes32 paymentId = keccak256(abi.encode("pact-payment", paymentNonce));

        (address resolved,) = registry.getMerchant(merchantId);
        bool active = registry.isMerchantActive(merchantId);

        try executor.executePayment(paymentId, merchantId, address(usdc), amount, purposeHash) {
            // Success is only legal for an active merchant paid at its registered wallet.
            assertTrue(active);
            assertEq(resolved, wallet);
            expectedReceived[wallet] += amount;
            lastPaymentId = paymentId;
            lastMerchantId = merchantId;
            lastAmount = amount;
            lastPurposeHash = purposeHash;
            hasLastPayment = true;
        } catch {
            // Inactive/unknown merchants must never be paid; balances prove it.
        }
    }

    function toggleStatus(uint256 merchantSeed, bool active) external {
        if (merchantIds.length == 0) return;
        bytes32 merchantId = merchantIds[merchantSeed % merchantIds.length];
        registry.setMerchantStatus(merchantId, active);
    }

    function registerFreshMerchant(uint256 walletSeed) external {
        if (merchantIds.length >= MAX_TRACKED_MERCHANTS) return;
        merchantNonce += 1;
        bytes32 merchantId = keccak256(abi.encode("pact-merchant", merchantNonce));
        address wallet = address(uint160(bound(walletSeed, 1, type(uint160).max)));
        if (
            wallet == address(this) || wallet == address(executor) || wallet == address(usdc)
                || wallet == address(registry) || walletUsed[wallet]
        ) return;
        walletUsed[wallet] = true;
        merchantIds.push(merchantId);
        merchantWallet[merchantId] = wallet;
        registry.registerMerchant(merchantId, wallet);
    }

    function replayLastPayment() external {
        if (!hasLastPayment) return;
        // A replayed payment id must ALWAYS revert, whatever the merchant state.
        (bool ok,) = address(executor)
            .call(
                abi.encodeCall(
                    PactPaymentExecutor.executePayment,
                    (lastPaymentId, lastMerchantId, address(usdc), lastAmount, lastPurposeHash)
                )
            );
        assert(!ok);
        assert(executor.usedPaymentIds(lastPaymentId));
    }

    // --- Ghost views for invariants ---

    function trackedMerchants() external view returns (bytes32[] memory) {
        return merchantIds;
    }

    function walletOf(bytes32 merchantId) external view returns (address) {
        return merchantWallet[merchantId];
    }

    function expectedOf(address wallet) external view returns (uint256) {
        return expectedReceived[wallet];
    }

    function minted() external view returns (uint256) {
        return mintedTotal;
    }
}

/// @title Pact security invariants.
contract PactInvariantsTest is Test {
    MockUSDC internal usdc;
    PactMerchantRegistry internal registry;
    PactPaymentExecutor internal executor;
    PactHandler internal handler;

    function setUp() public {
        registry = new PactMerchantRegistry();
        usdc = new MockUSDC();
        executor = new PactPaymentExecutor(address(registry), address(usdc));
        handler = new PactHandler(usdc, registry, executor);

        // Registry ownership moves to the handler so it can manage merchants.
        registry.transferOwnership(address(handler));

        // Seed three merchants with fixed wallets.
        handler.seedMerchant(keccak256("merchant-0"), makeAddr("m0"));
        handler.seedMerchant(keccak256("merchant-1"), makeAddr("m1"));
        handler.seedMerchant(keccak256("merchant-2"), makeAddr("m2"));
        handler.fund(10_000_000_000);

        targetContract(address(handler));

        // Fuzz only the operational entry points. seedMerchant is setUp-only:
        // fuzzing it with adversarial wallets would break ghost accounting in
        // the handler, not in the contracts under test.
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PactHandler.pay.selector;
        selectors[1] = PactHandler.toggleStatus.selector;
        selectors[2] = PactHandler.registerFreshMerchant.selector;
        selectors[3] = PactHandler.replayLastPayment.selector;
        selectors[4] = PactHandler.fund.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice The executor must never custody funds: every payment moves
    ///         USDC directly from payer to merchant.
    function invariant_executorHoldsNoFunds() public view {
        assertEq(usdc.balanceOf(address(executor)), 0);
    }

    /// @notice Every tracked merchant holds exactly what successful payments sent it:
    ///         no more (no double-spend / wrong-recipient) and no less (no skimming).
    function invariant_merchantBalancesMatchExpected() public view {
        bytes32[] memory ids = handler.trackedMerchants();
        for (uint256 i = 0; i < ids.length; i++) {
            address wallet = handler.walletOf(ids[i]);
            assertEq(usdc.balanceOf(wallet), handler.expectedOf(wallet));
        }
    }

    /// @notice Conservation: handler + merchants hold the entire minted supply,
    ///         so no USDC can leak to the executor, zero address, or elsewhere.
    function invariant_supplyConservation() public view {
        uint256 accounted = usdc.balanceOf(address(handler));
        bytes32[] memory ids = handler.trackedMerchants();
        for (uint256 i = 0; i < ids.length; i++) {
            accounted += usdc.balanceOf(handler.walletOf(ids[i]));
        }
        assertEq(accounted, usdc.totalSupply());
        assertEq(usdc.totalSupply(), handler.minted());
        assertEq(usdc.balanceOf(address(0)), 0);
    }

    /// @notice Payment ids are single-use: the handler replays the last successful
    ///         payment id on every `replayLastPayment` call and asserts the replay
    ///         reverts, so any duplicate-execution bug fails the invariant run.
    ///         Failed payments consume no ids because the flag is set immediately
    ///         before a transfer that reverts the whole transaction (including the
    ///         flag) on failure — see unit test
    ///         test_RevertingTokenTransfer_RollsBackAndAllowsRetry for the proof.
}
