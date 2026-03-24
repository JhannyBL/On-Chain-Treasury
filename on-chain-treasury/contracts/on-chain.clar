;; VaultDAO - On-Chain Treasury Coordination
;; A lightweight DAO treasury with quorum-gated disbursements

(define-constant FOUNDER tx-sender)
(define-constant MIN-DEPOSIT u10000000)        ;; 10 STX minimum
(define-constant QUORUM-THRESHOLD u6000)       ;; 60% in basis points
(define-constant BASIS u10000)

(define-constant ERR-NOT-MEMBER (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-BAD-AMOUNT (err u102))
(define-constant ERR-NO-PROPOSAL (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-WINDOW-CLOSED (err u105))
(define-constant ERR-QUORUM-UNMET (err u106))
(define-constant ERR-ALREADY-EXECUTED (err u107))
(define-constant ERR-TRANSFER-FAILED (err u108))
(define-constant ERR-NOT-FOUNDER (err u109))
(define-constant ERR-VETOED (err u110))
(define-constant ERR-INSUFFICIENT-FUNDS (err u111))

;; Member deposit weights (in micro-STX)
(define-map member-registry
    principal
    { deposit: uint, joined-at: uint }
)

;; Proposal ledger
(define-map proposal-ledger
    uint
    {
        proposer: principal,
        recipient: principal,
        amount: uint,
        memo: (string-utf8 200),
        yes-weight: uint,
        no-weight: uint,
        open-until: uint,
        executed: bool,
        vetoed: bool
    }
)

;; Per-member vote tracking: (proposal-id, voter) voted?
(define-map vote-records
    { pid: uint, voter: principal }
    bool
)

(define-data-var proposal-count uint u0)
(define-data-var total-deposited uint u0)

(define-read-only (get-proposal (pid uint))
    (map-get? proposal-ledger pid)
)

(define-read-only (get-member-weight (addr principal))
    (match (map-get? member-registry addr)
        m (get deposit m)
        u0
    )
)

(define-read-only (is-member (addr principal))
    (is-some (map-get? member-registry addr))
)

(define-read-only (get-total-deposited)
    (var-get total-deposited)
)

(define-read-only (get-proposal-count)
    (var-get proposal-count)
)

(define-read-only (has-voted (pid uint) (addr principal))
    (default-to false (map-get? vote-records { pid: pid, voter: addr }))
)

(define-private (quorum-reached (yes-w uint) (total-w uint))
    (if (is-eq total-w u0)
        false
        (>= (* yes-w BASIS) (* total-w QUORUM-THRESHOLD))
    )
)

;; Deposit STX to register as a member
(define-public (join-vault (amount uint))
    (begin
        (asserts! (>= amount MIN-DEPOSIT) ERR-BAD-AMOUNT)
        (asserts! (not (is-member tx-sender)) ERR-ALREADY-MEMBER)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set member-registry tx-sender
            { deposit: amount, joined-at: block-height }
        )
        (var-set total-deposited (+ (var-get total-deposited) amount))
        (ok true)
    )
)

;; Submit a disbursement proposal
(define-public (submit-proposal
    (recipient principal)
    (amount uint)
    (window-blocks uint)
    (memo (string-utf8 200)))
    (begin
        (asserts! (is-member tx-sender) ERR-NOT-MEMBER)
        (asserts! (> amount u0) ERR-BAD-AMOUNT)
        (asserts! (> window-blocks u0) ERR-BAD-AMOUNT)
        (asserts! (<= amount (stx-get-balance (as-contract tx-sender)))
            ERR-INSUFFICIENT-FUNDS)
        (let ((pid (+ (var-get proposal-count) u1)))
            (map-set proposal-ledger pid
                {
                    proposer: tx-sender,
                    recipient: recipient,
                    amount: amount,
                    memo: memo,
                    yes-weight: u0,
                    no-weight: u0,
                    open-until: (+ block-height window-blocks),
                    executed: false,
                    vetoed: false
                }
            )
            (var-set proposal-count pid)
            (ok pid)
        )
    )
)

;; Cast a weighted vote
(define-public (cast-vote (pid uint) (in-favor bool))
    (let (
        (proposal (unwrap! (map-get? proposal-ledger pid) ERR-NO-PROPOSAL))
        (weight (get-member-weight tx-sender))
    )
        (asserts! (> weight u0) ERR-NOT-MEMBER)
        (asserts! (not (get vetoed proposal)) ERR-VETOED)
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        (asserts! (<= block-height (get open-until proposal)) ERR-WINDOW-CLOSED)
        (asserts! (not (has-voted pid tx-sender)) ERR-ALREADY-VOTED)
        (map-set vote-records { pid: pid, voter: tx-sender } true)
        (if in-favor
            (map-set proposal-ledger pid
                (merge proposal { yes-weight: (+ (get yes-weight proposal) weight) }))
            (map-set proposal-ledger pid
                (merge proposal { no-weight: (+ (get no-weight proposal) weight) }))
        )
        (ok true)
    )
)

;; Execute proposal if quorum is met
(define-public (execute-proposal (pid uint))
    (let (
        (proposal (unwrap! (map-get? proposal-ledger pid) ERR-NO-PROPOSAL))
        (total-w (var-get total-deposited))
    )
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        (asserts! (not (get vetoed proposal)) ERR-VETOED)
        (asserts! (<= block-height (get open-until proposal)) ERR-WINDOW-CLOSED)
        (asserts!
            (quorum-reached (get yes-weight proposal) total-w)
            ERR-QUORUM-UNMET)
        (map-set proposal-ledger pid (merge proposal { executed: true }))
        (as-contract
            (stx-transfer? (get amount proposal) tx-sender (get recipient proposal))
        )
    )
)

;; Founder veto kills a proposal before execution
(define-public (veto-proposal (pid uint))
    (let ((proposal (unwrap! (map-get? proposal-ledger pid) ERR-NO-PROPOSAL)))
        (asserts! (is-eq tx-sender FOUNDER) ERR-NOT-FOUNDER)
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        (map-set proposal-ledger pid (merge proposal { vetoed: true }))
        (ok true)
    )
)