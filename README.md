# Pact — Phase 1: Smart-Contract Layer (Arc Testnet)

Pact is an AI agent for controlled USDC payments. **Phase 1 is strictly the smart-contract
layer**: a merchant registry plus a single-payment USDC executor, built and tested with Foundry.
No backend, database, OpenAI integration, frontend, Clerk auth, or MetaMask UI exists in this
repository — and none was added in this phase.

The repo directory was empty when Phase 1 started, so this is a clean rebuild (no old Pact
contracts were reused).

## Target network (all values verified, none invented)

| Parameter | Value | Source |
| --- | --- | --- |
| Network | Arc Testnet | `docs.arc.io/arc/references/connect-to-arc` |
| Chain ID | `5042002` (`0x4CEF52`) | confirmed live via `cast chain-id` on `https://rpc.testnet.arc.io` |
| RPC | `https://rpc.testnet.arc.io` | `docs.arc.io/arc/references/rpc-endpoints` |
| Explorer | `https://testnet.arcscan.app` (Blockscout) | `docs.arc.io/arc/tutorials/deploy-on-arc` |
| USDC | `0x3600000000000000000000000000000000000000` | `docs.arc.io/arc/references/contract-addresses`, Circle developer docs |
| USDC decimals | 6 on the ERC-20 view, 18 natively (same balance, two views) | Arc stablecoin-native model docs |
| EVM target | Osaka hard fork | `docs.arc.io/arc/references/evm-differences` |
| Faucet | `https://faucet.circle.com` | Arc docs |

Compiler choice follows from the above: **solc `0.8.37`** (latest stable at time of writing,
verified downloadable) pinned in `foundry.toml` + exact pragma, with
**`evm_version = "osaka"`** matching Arc's documented EVM baseline. The only external
dependency is **OpenZeppelin Contracts `v5.7.0`** (pinned submodule), used solely for
`IERC20` + `SafeERC20`.

> **No live deployment has been broadcast.** All Arc Testnet runs so far are read-only
> simulations. Broadcasting requires explicit approval (see Deployment).

## Contracts

### `src/PactMerchantRegistry.sol`

- `registerMerchant(bytes32 merchantId, address wallet)` — owner-only. Rejects zero ids,
  zero-address wallets, and duplicate ids. New merchants start **active**.
- `setMerchantStatus(bytes32 merchantId, bool active)` — owner-only activation/deactivation.
  Unknown ids revert.
- `getMerchant(bytes32)` → `(wallet, active)`; unknown ids return `(address(0), false)`.
- `isMerchantActive(bytes32)` → `bool`; unknown ids return `false`.
- `transferOwnership(address)` — owner-only, zero address rejected.
- Events: `MerchantRegistered`, `MerchantStatusChanged`, `OwnershipTransferred`.
- Custom errors, no inheritance, no funds held, no upgradeability.

### `src/PactPaymentExecutor.sol`

- `executePayment(paymentId, merchantId, token, amount, purposeHash)` — pulls USDC from
  `msg.sender` (the payer, who must `approve` first) directly to the merchant wallet.
  - Rejects: empty payment id, reused payment id, non-USDC `token`, zero amount,
    unknown merchant, inactive merchant, zero recipient.
  - Marks the payment id used **before** the external call (checks-effects-interactions);
    a failed transfer reverts the whole transaction, so failed payments consume no ids.
  - Emits `PaymentExecuted(paymentId, merchantId, merchant, payer, token, amount,
    purposeHash, block.timestamp)`.
- `registry` and `usdc` are **`immutable`** — there are no setters, no admin functions, and
  no fallback, so the configured USDC token cannot be silently changed (covered by
  `test_NoSilentReconfiguration`).
- Uses OpenZeppelin `SafeERC20` (handles non-standard tokens that return no data / false).
- Explicitly out of scope: AI decisions, natural-language parsing, OpenAI calls, multi-chain
  routing, Solana/Sui, credit scoring, virtual cards, recurring payments, refunds, fiat/MoMo.

## Project layout

```
src/                        PactMerchantRegistry.sol, PactPaymentExecutor.sol
test/                       unit tests + invariant tests
test/mocks/MockUSDC.sol     6-decimal ERC-20 stand-in with sabotage switches (tests/local only)
script/                     DeployRegistry / DeployExecutor / RegisterMerchant
lib/                        openzeppelin-contracts@v5.7.0 (submodule; IERC20 + SafeERC20 only)
foundry.toml  .env.example  remappings.txt  README.md
```

## Build, test, format, lint

```sh
forge build
forge test                      # 26 unit tests + 3 invariant tests (256 runs each)
forge fmt --check && forge fmt
forge lint                      # clean for src/, test/, script/ (only upstream forge-std warnings)
```

## Local end-to-end (Anvil, verified working)

```sh
anvil --port 8545 &  # local chain id 31337
KEY=<anvil key 0> DEPLOYER=<anvil account 0> RPC=http://127.0.0.1:8545

# 1. Mock USDC (stand-in; Arc's real USDC precompile exists only on testnet)
forge create test/mocks/MockUSDC.sol:MockUSDC --rpc-url $RPC --private-key $KEY --broadcast
# 2-3. Registry + executor
export ARC_TESTNET_RPC_URL=$RPC PRIVATE_KEY=$KEY DEPLOYER_ADDRESS=$DEPLOYER USDC_ADDRESS=<mock>
export REGISTRY_ADDRESS=$(forge script script/DeployRegistry.s.sol:DeployRegistry \
  --rpc-url $RPC --broadcast | grep "deployed at" | awk '{print $NF}')
forge script script/DeployExecutor.s.sol:DeployExecutor --rpc-url $RPC --broadcast
# 4. Register merchant, fund payer, approve, pay via cast — see test/PactPaymentExecutor.t.sol
#    for the exact flow. Verified locally: payer 1000→750, merchant 0→250 mUSDC,
#    executor balance 0, PaymentExecuted emitted, duplicate/unknown rejections revert.
```

## Arc Testnet deployment (prepare, do NOT broadcast without approval)

```sh
cp .env.example .env  # fill PRIVATE_KEY / DEPLOYER_ADDRESS / addresses; .env is gitignored
# 1. SIMULATE first (read-only, no --broadcast):
forge script script/DeployRegistry.s.sol:DeployRegistry --rpc-url arc_testnet
forge script script/DeployExecutor.s.sol:DeployExecutor --rpc-url arc_testnet
forge script script/RegisterMerchant.s.sol:RegisterMerchant --rpc-url arc_testnet
# 2. Only after reviewing the simulation AND with explicit approval, add --broadcast.
# 3. Verify on the Blockscout explorer:
forge verify-contract <ADDRESS> src/PactMerchantRegistry.sol:PactMerchantRegistry \
  --chain-id 5042002 --verifier blockscout --verifier-url https://testnet.arcscan.app/api/
```

Scripts read all config from env and fail fast on missing/zero values or a
`PRIVATE_KEY`/`DEPLOYER_ADDRESS` mismatch. They log deployed addresses, registry/USDC
configuration, and chain id; transaction hashes appear in the forge broadcast output and
`broadcast/` receipts. Current status: **simulation passes on Arc Testnet
(`chainId: 5042002`); nothing broadcast.**

## Arc-specific notes affecting these contracts

- Zero-address native transfers revert on Arc; the contracts additionally never target
  `address(0)` (registration-time + execution-time guards).
- Keep payment math in the **6-decimal ERC-20 view**; never mix with 18-decimal native units.
- Arc mempool enforces a **20 Gwei `maxFeePerGas` floor** — set fees accordingly when
  broadcasting, or transactions are silently dropped.
- No `PREVRANDAO` randomness, no blob transactions; neither is used here.

## Known limitations

- No third-party audit; static analysis is Foundry build warnings + `forge lint` (Slither
  not installed in this environment).
- `MockUSDC` is a test double: real Arc USDC (`0x3600…0000`) is a system-level ERC-20
  interface and can only be exercised on testnet after an approved broadcast.
- `forge script` required a `forge clean` rebuild once due to a stale build-info cache;
  documented here in case it recurs (harmless, simulation-only symptom).
- Invariant suite takes ~90s (3 × 256 runs × 500 calls); unit tests run in milliseconds.

## Phase 2 — exact next step

**Broadcast the verified deployment to Arc Testnet, then build the confirmation-first
offboarding service around it:** (1) get explicit approval and `--broadcast` the three
scripts in order (registry → executor → merchant registration) with `USDC_ADDRESS=
0x3600000000000000000000000000000000000000`; (2) fund the deployer via
`faucet.circle.com` first (USDC pays gas); (3) verify both contracts on
`testnet.arcscan.app`; (4) only then start Phase 2 backend work — payer confirmation flow
that mints payment ids + purpose hashes off-chain and submits `executePayment` after the
user confirms. No contract changes are expected for that step.

## License

**Business Source License 1.1** (see `LICENSE`). You may copy, modify, and use this
codebase for **non-production purposes only** (development, testing, evaluation, research,
personal use). **No production or commercial use — including paid, freemium, hosted,
managed, or SaaS offerings — without a separate commercial license** from the repository
owner. Each version converts to **Apache 2.0** on its Change Date (`2030-09-22` for this
release). Third-party code under `lib/` retains its own licenses.
