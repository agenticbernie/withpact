// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.37;

/// @title IPactMerchantRegistry
/// @notice Minimal read interface consumed by {PactPaymentExecutor}.
interface IPactMerchantRegistry {
    /// @notice Returns the wallet and active flag for a merchant id.
    /// @dev Unknown ids return `(address(0), false)`.
    function getMerchant(bytes32 merchantId) external view returns (address wallet, bool active);

    /// @notice Returns true only for registered merchants whose status is active.
    /// @dev Unknown ids return false.
    function isMerchantActive(bytes32 merchantId) external view returns (bool);
}

/// @title PactMerchantRegistry
/// @notice Phase 1 (PoC) registry of merchants allowed to receive Pact USDC payments on Arc Testnet.
/// @dev Registration and status changes are owner-only. The contract holds no funds,
///      is not upgradeable, and has no dependencies beyond the Solidity compiler.
contract PactMerchantRegistry is IPactMerchantRegistry {
    /// @notice Merchant record. `wallet == address(0)` means "never registered".
    struct Merchant {
        address wallet;
        bool active;
    }

    /// @notice Administrative owner. Set once at deployment, transferable via {transferOwnership}.
    address public owner;

    mapping(bytes32 => Merchant) private merchants;

    event MerchantRegistered(bytes32 indexed merchantId, address indexed wallet);
    event MerchantStatusChanged(bytes32 indexed merchantId, bool active);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error InvalidMerchantId();
    error DuplicateMerchant();
    error UnknownMerchant();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Registers a merchant. New merchants start active.
    /// @param merchantId Unique merchant identifier (e.g. keccak256 of an off-chain slug).
    /// @param wallet Merchant payout wallet. Must not be the zero address.
    function registerMerchant(bytes32 merchantId, address wallet) external onlyOwner {
        if (merchantId == bytes32(0)) revert InvalidMerchantId();
        if (wallet == address(0)) revert ZeroAddress();
        if (merchants[merchantId].wallet != address(0)) revert DuplicateMerchant();

        merchants[merchantId] = Merchant({wallet: wallet, active: true});
        emit MerchantRegistered(merchantId, wallet);
    }

    /// @notice Activates or deactivates a registered merchant.
    /// @dev Only registered merchants have a status; unknown ids revert.
    function setMerchantStatus(bytes32 merchantId, bool active) external onlyOwner {
        if (merchants[merchantId].wallet == address(0)) revert UnknownMerchant();

        merchants[merchantId].active = active;
        emit MerchantStatusChanged(merchantId, active);
    }

    /// @inheritdoc IPactMerchantRegistry
    function getMerchant(bytes32 merchantId) external view returns (address wallet, bool active) {
        Merchant memory m = merchants[merchantId];
        return (m.wallet, m.active);
    }

    /// @inheritdoc IPactMerchantRegistry
    function isMerchantActive(bytes32 merchantId) external view returns (bool) {
        return merchants[merchantId].active;
    }

    /// @notice Transfers administration to a new owner.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
