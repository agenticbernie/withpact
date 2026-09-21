// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPactMerchantRegistry} from "./PactMerchantRegistry.sol";

/// @title PactPaymentExecutor
/// @notice Executes single, confirmation-first USDC payments to active registered merchants.
/// @dev Pull model: the payer must approve this contract, then call {executePayment}.
///      The contract never holds protocol funds, has no admin functions (registry and
///      USDC addresses are immutable), performs no AI decisions, and targets one chain
///      (Arc Testnet, chain id 5042002). Follows checks-effects-interactions.
contract PactPaymentExecutor {
    using SafeERC20 for IERC20;

    /// @notice Registry used to resolve and validate merchants. Immutable.
    IPactMerchantRegistry public immutable registry;

    /// @notice The only token this contract can move (USDC on Arc Testnet). Immutable,
    /// @dev so it cannot be silently swapped after deployment.
    IERC20 public immutable usdc;

    /// @notice Payment ids that have already been executed. Each id executes at most once.
    mapping(bytes32 => bool) public usedPaymentIds;

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

    error ZeroAddress();
    error InvalidPaymentId();
    error DuplicatePaymentId();
    error UnsupportedToken();
    error ZeroAmount();
    error UnknownMerchant();
    error InactiveMerchant();
    error ZeroRecipient();

    constructor(address registry_, address usdc_) {
        if (registry_ == address(0) || usdc_ == address(0)) revert ZeroAddress();
        registry = IPactMerchantRegistry(registry_);
        usdc = IERC20(usdc_);
    }

    /// @notice Executes one USDC payment from the caller to an active registered merchant.
    /// @param paymentId Unique payment id. Reused ids revert, so each payment runs at most once.
    /// @param merchantId Registered merchant id. Unknown or inactive merchants revert.
    /// @param token Must equal the configured USDC address; anything else reverts.
    /// @param amount USDC base units (6 decimals on the ERC-20 view). Must be greater than zero.
    /// @param purposeHash Off-chain intent binding (e.g. keccak256 of order id / purpose).
    ///                    Zero is allowed when the caller has no metadata to bind.
    function executePayment(bytes32 paymentId, bytes32 merchantId, address token, uint256 amount, bytes32 purposeHash)
        external
    {
        // Checks.
        if (paymentId == bytes32(0)) revert InvalidPaymentId();
        if (usedPaymentIds[paymentId]) revert DuplicatePaymentId();
        if (token != address(usdc)) revert UnsupportedToken();
        if (amount == 0) revert ZeroAmount();

        (address wallet,) = registry.getMerchant(merchantId);
        if (!registry.isMerchantActive(merchantId)) {
            // Distinguish never-registered ids from deactivated merchants.
            if (wallet == address(0)) revert UnknownMerchant();
            revert InactiveMerchant();
        }
        // Defense in depth: an active record must always resolve to a payable
        // wallet. Unreachable through the honest registry (which rejects zero
        // wallets at registration), but this guarantees the function can never
        // route funds to address(0) even if the registry view misbehaves.
        if (wallet == address(0)) revert ZeroRecipient();

        // Effects.
        usedPaymentIds[paymentId] = true;

        // Interactions. Reverts (rolling back the marking above) if the payer
        // has not approved enough USDC or the token transfer otherwise fails.
        usdc.safeTransferFrom(msg.sender, wallet, amount);

        emit PaymentExecuted(paymentId, merchantId, wallet, msg.sender, token, amount, purposeHash, block.timestamp);
    }
}
