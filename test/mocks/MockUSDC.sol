// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
pragma solidity 0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Test-only USDC stand-in with 6 decimals (matching the ERC-20 view of
///         USDC on Arc Testnet). Includes sabotage switches so tests can prove a
///         failed token transfer reverts the whole payment.
/// @dev Never deployed to testnet; local/anvil and forge tests only.
contract MockUSDC is ERC20 {
    error TransferFailed();

    /// @notice When true, transferFrom reverts.
    bool public failRevert;
    /// @notice When true, transferFrom silently returns false (non-standard token behavior).
    bool public failSilent;

    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFailRevert(bool v) external {
        failRevert = v;
    }

    function setFailSilent(bool v) external {
        failSilent = v;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (failRevert) revert TransferFailed();
        if (failSilent) return false;
        return super.transferFrom(from, to, value);
    }
}
