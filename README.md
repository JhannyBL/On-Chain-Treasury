# VaultDAO

A minimalist treasury coordination protocol built on the Stacks blockchain.
VaultDAO enables decentralized organizations to manage pooled funds through
time-locked proposals, quorum-based approvals, and transparent disbursements.

## Overview

VaultDAO solves the coordination problem for multi-sig treasuries by replacing
off-chain agreements with on-chain enforcement. Any registered member can
submit a spending proposal; the protocol handles quorum tracking, vote
expiry, and atomic fund release.

## Features

- Member registry with deposit-based admission
- Proposal creation with configurable execution windows
- Weighted quorum voting (yes/no)
- Automatic proposal expiry enforcement
- Direct STX disbursement on approval
- Emergency veto by founding principal

## Architecture
```
┌─────────────────────────────────────┐
│            VaultDAO Contract         │
├─────────────┬───────────────────────┤
│  member-     │  proposal-            │
│  registry   │  ledger               │
├─────────────┼───────────────────────┤
│  vote-      │  treasury-            │
│  records    │  balance (var)        │
└─────────────┴───────────────────────┘
```

Storage is intentionally flat — no nested maps. Each domain has its own map.

## Function Descriptions

| Function | Type | Description |
|---|---|---|
| `join-vault` | public | Deposit STX to become a member |
| `submit-proposal` | public | Propose a treasury disbursement |
| `cast-vote` | public | Vote yes or no on a proposal |
| `execute-proposal` | public | Release funds if quorum met and window open |
| `get-proposal` | read-only | Fetch proposal details |
| `get-member-weight` | read-only | Fetch a member's voting weight |
| `is-member` | read-only | Check membership status |

## Example Usage
```clarity
;; Join the vault with 500 STX
(contract-call? .vault-dao join-vault u500000000)

;; Propose sending 100 STX to a grantee
(contract-call? .vault-dao submit-proposal
  'SP2... u100000000 u1440 "Q3 grant disbursement")

;; Vote in favor
(contract-call? .vault-dao cast-vote u1 true)

;; Execute after quorum
(contract-call? .vault-dao execute-proposal u1)
```

## Security Considerations

- Members cannot vote twice on the same proposal
- Proposals auto-expire after the defined window
- Execution checks quorum at call-time, not at vote-time
- Only the founding principal can veto an active proposal
- Minimum deposit enforced to prevent Sybil admission
