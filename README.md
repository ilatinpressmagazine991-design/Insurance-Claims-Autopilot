# Insurance-Claims-Autopilot

A simple, end-to-end claims workflow demo built with Clarinet and Clarity. It models two independent smart contracts that do not call each other or use traits:

- intake-and-triage: First Notice of Loss (FNOL), photo evidence references, policy registry, and basic severity scoring.
- adjudication: Damage assessment inputs, fraud signal capture, adjuster assignment, and settlement approval tracking.

This project is intentionally minimal yet complete: clean Clarity code, clear data models, and straightforward public functions.

## Architecture

- No cross-contract calls or trait usage.
- Two contracts living in the same project under `contracts/`:
  - `intake-and-triage.clar` manages policies and new claims intake.
  - `adjudication.clar` records assessment artifacts and settlement approvals.
- Storage is kept compact and strictly typed; all state transitions are explicit.

## Features

### intake-and-triage
- Register and deactivate policies
- Open a claim (FNOL) with a short description and a photo hash buffer
- Compute and store a simple, deterministic severity score
- Read-only getters for policies and claims

### adjudication
- Register/remove adjusters and assign them to claims
- Record structured damage inputs and fraud signals
- Compute damage and fraud scores deterministically (no off-chain calls)
- Propose and approve claim settlements with status tracking

## File structure

- Clarinet.toml – Clarinet workspace configuration
- contracts/
  - intake-and-triage.clar – Intake and policy/claim storage and scoring
  - adjudication.clar – Assessment, fraud, and settlement tracking
- settings/ – Chain configuration files for Devnet/Testnet/Mainnet
- tests/ – Auto-generated tests (you can extend or replace)
- package.json – NPM project file used by Clarinet tooling

## Development

Prerequisites: Clarinet and GitHub CLI installed and authenticated.

Common commands:
- clarinet check – Lints and type-checks all Clarity contracts
- clarinet console – Interact with contracts locally
- clarinet test – Run tests (extend `tests/` as desired)

## Data model summary

### intake-and-triage
- policies: (policy-id) → { holder, coverage-limit, active }
- claims: (claim-id) → { policy-id, claimant, description, photo-hash, status, severity, created-at }

### adjudication
- adjusters: principal → bool
- assignments: (claim-id) → { adjuster }
- damages: (claim-id) → { est-repair-cost, total-loss, mileage, pre-existing-damage, ai-score }
- fraud: (claim-id) → { late-reporting, prior-claims, suspicious-pattern, ip-distance, fraud-score }
- settlements: (claim-id) → { amount, status }

## Notes

- These contracts are examples for instructional purposes; they’re not production-ready.
- There are no token transfers or external calls; all scoring is on-chain and deterministic.