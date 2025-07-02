(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-QUORUM-NOT-MET (err u105))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u106))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u107))

(define-data-var proposal-count uint u0)
(define-data-var min-proposal-duration uint u144)
(define-data-var quorum-threshold uint u500)
(define-data-var voting-token (optional principal) none)

(define-map proposals
    uint 
    {
        creator: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        start-height: uint,
        end-height: uint,
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20),
        execution-params: (list 10 principal)
    }
)

(define-map votes 
    { proposal-id: uint, voter: principal } 
    { vote: bool }
)

(define-map member-weights
    principal
    uint
)

(define-public (initialize-dao (token principal))
    (begin
        (var-set voting-token (some token))
        (ok true)))

(define-public (create-proposal 
    (title (string-ascii 50))
    (description (string-ascii 500))
    (duration uint)
    (execution-params (list 10 principal)))
    (let
        ((proposal-id (+ (var-get proposal-count) u1))
         (start-block stacks-block-height)
         (end-block (+ start-block duration)))
        (asserts! (>= duration (var-get min-proposal-duration)) ERR-INVALID-PROPOSAL)
        (map-set proposals proposal-id
            {
                creator: tx-sender,
                title: title,
                description: description,
                start-height: start-block,
                end-height: end-block,
                yes-votes: u0,
                no-votes: u0,
                status: "active",
                execution-params: execution-params
            })
        (var-set proposal-count proposal-id)
        (ok proposal-id)))

(define-public (cast-vote (proposal-id uint) (vote bool))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
         (voter-weight (default-to u0 (map-get? member-weights tx-sender))))
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (>= stacks-block-height (get start-height proposal)) ERR-INVALID-PROPOSAL)
        (asserts! (<= stacks-block-height (get end-height proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
        (map-set votes {proposal-id: proposal-id, voter: tx-sender} {vote: vote})
        (if vote
            (map-set proposals proposal-id 
                (merge proposal {yes-votes: (+ (get yes-votes proposal) voter-weight)}))
            (map-set proposals proposal-id 
                (merge proposal {no-votes: (+ (get no-votes proposal) voter-weight)})))
        (ok true)))

(define-public (finalize-proposal (proposal-id uint))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
         (total-votes (+ (get yes-votes proposal) (get no-votes proposal))))
        (asserts! (>= stacks-block-height (get end-height proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (>= total-votes (var-get quorum-threshold)) ERR-QUORUM-NOT-MET)
        (map-set proposals proposal-id
            (merge proposal 
                {status: (if (> (get yes-votes proposal) (get no-votes proposal)) 
                    "passed" 
                    "rejected")}))
        (ok true)))

(define-public (set-member-weight (member principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (map-set member-weights member weight)
        (ok true)))

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id))

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter}))

(define-read-only (get-member-weight (member principal))
    (default-to u0 (map-get? member-weights member)))

(define-read-only (get-total-proposals)
    (var-get proposal-count))

(define-read-only (can-vote (proposal-id uint) (voter principal))
    (match (map-get? proposals proposal-id)
        proposal (ok (and
            (is-eq (get status proposal) "active")
            (>= stacks-block-height (get start-height proposal))
            (<= stacks-block-height (get end-height proposal))
            (is-none (map-get? votes {proposal-id: proposal-id, voter: voter}))))
        ERR-PROPOSAL-NOT-FOUND))