(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-QUORUM-NOT-MET (err u105))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u106))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u107))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u108))
(define-constant ERR-AMENDMENT-NOT-FOUND (err u109))
(define-constant ERR-AMENDMENT-EXPIRED (err u110))
(define-constant ERR-CANNOT-AMEND-FINALIZED (err u111))

(define-data-var proposal-count uint u0)
(define-data-var amendment-count uint u0)
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

(define-map delegations
    principal
    principal
)

(define-map amendments
    uint
    {
        proposal-id: uint,
        creator: principal,
        new-title: (string-ascii 50),
        new-description: (string-ascii 500),
        submission-height: uint,
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20)
    }
)

(define-map amendment-votes
    { amendment-id: uint, voter: principal }
    { vote: bool }
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

(define-read-only (get-total-voting-power (member principal))
    (+ (default-to u0 (map-get? member-weights member)) u0))

(define-public (cast-vote (proposal-id uint) (vote bool))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
         (voter-weight (get-total-voting-power tx-sender)))
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

(define-public (delegate-to (delegate principal))
    (begin
        (asserts! (not (is-eq tx-sender delegate)) ERR-CANNOT-DELEGATE-TO-SELF)
        (map-set delegations tx-sender delegate)
        (ok true)))

(define-public (undelegate)
    (begin
        (map-delete delegations tx-sender)
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

(define-read-only (get-delegate (member principal))
    (map-get? delegations member))

(define-read-only (get-delegation-status (member principal))
    (match (map-get? delegations member)
        delegate (some delegate)
        none))

(define-public (submit-amendment 
    (proposal-id uint)
    (new-title (string-ascii 50))
    (new-description (string-ascii 500)))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
         (amendment-id (+ (var-get amendment-count) u1)))
        (asserts! (is-eq (get status proposal) "active") ERR-CANNOT-AMEND-FINALIZED)
        (asserts! (<= stacks-block-height (get end-height proposal)) ERR-AMENDMENT-EXPIRED)
        (map-set amendments amendment-id
            {
                proposal-id: proposal-id,
                creator: tx-sender,
                new-title: new-title,
                new-description: new-description,
                submission-height: stacks-block-height,
                yes-votes: u0,
                no-votes: u0,
                status: "pending"
            })
        (var-set amendment-count amendment-id)
        (ok amendment-id)))

(define-public (vote-on-amendment (amendment-id uint) (vote bool))
    (let
        ((amendment (unwrap! (map-get? amendments amendment-id) ERR-AMENDMENT-NOT-FOUND))
         (proposal (unwrap! (map-get? proposals (get proposal-id amendment)) ERR-PROPOSAL-NOT-FOUND))
         (voter-weight (get-total-voting-power tx-sender)))
        (asserts! (is-eq (get status amendment) "pending") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (is-eq (get status proposal) "active") ERR-CANNOT-AMEND-FINALIZED)
        (asserts! (<= stacks-block-height (get end-height proposal)) ERR-AMENDMENT-EXPIRED)
        (asserts! (is-none (map-get? amendment-votes {amendment-id: amendment-id, voter: tx-sender})) ERR-ALREADY-VOTED)
        (map-set amendment-votes {amendment-id: amendment-id, voter: tx-sender} {vote: vote})
        (if vote
            (map-set amendments amendment-id 
                (merge amendment {yes-votes: (+ (get yes-votes amendment) voter-weight)}))
            (map-set amendments amendment-id 
                (merge amendment {no-votes: (+ (get no-votes amendment) voter-weight)})))
        (ok true)))

(define-public (apply-amendment (amendment-id uint))
    (let
        ((amendment (unwrap! (map-get? amendments amendment-id) ERR-AMENDMENT-NOT-FOUND))
         (proposal (unwrap! (map-get? proposals (get proposal-id amendment)) ERR-PROPOSAL-NOT-FOUND))
         (total-amendment-votes (+ (get yes-votes amendment) (get no-votes amendment))))
        (asserts! (is-eq (get status amendment) "pending") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (is-eq (get status proposal) "active") ERR-CANNOT-AMEND-FINALIZED)
        (asserts! (>= total-amendment-votes (/ (var-get quorum-threshold) u2)) ERR-QUORUM-NOT-MET)
        (asserts! (> (get yes-votes amendment) (get no-votes amendment)) ERR-INVALID-PROPOSAL)
        (map-set proposals (get proposal-id amendment)
            (merge proposal
                {
                    title: (get new-title amendment),
                    description: (get new-description amendment)
                }))
        (map-set amendments amendment-id
            (merge amendment {status: "applied"}))
        (ok true)))

(define-read-only (get-amendment (amendment-id uint))
    (map-get? amendments amendment-id))

(define-read-only (get-amendment-vote (amendment-id uint) (voter principal))
    (map-get? amendment-votes {amendment-id: amendment-id, voter: voter}))

(define-read-only (get-total-amendments)
    (var-get amendment-count))
