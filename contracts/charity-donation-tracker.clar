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
(define-constant ERR-TREASURY-INSUFFICIENT-BALANCE (err u112))
(define-constant ERR-TIMELOCK-NOT-EXPIRED (err u113))
(define-constant ERR-WITHDRAWAL-NOT-FOUND (err u114))
(define-constant ERR-WITHDRAWAL-ALREADY-EXECUTED (err u115))
(define-constant ERR-TREASURY-PAUSED (err u116))
(define-constant ERR-CHARITY-NOT-FOUND (err u117))
(define-constant ERR-INVALID-DONATION (err u118))
(define-constant ERR-IMPACT-REPORT-NOT-FOUND (err u119))
(define-constant ERR-BADGE-ALREADY-EARNED (err u120))

(define-data-var proposal-count uint u0)
(define-data-var amendment-count uint u0)
(define-data-var min-proposal-duration uint u144)
(define-data-var quorum-threshold uint u500)
(define-data-var voting-token (optional principal) none)
(define-data-var withdrawal-count uint u0)
(define-data-var timelock-duration uint u1008)
(define-data-var treasury-paused bool false)
(define-data-var charity-count uint u0)
(define-data-var donation-count uint u0)
(define-data-var total-donations-tracked uint u0)
(define-data-var impact-report-count uint u0)

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
    { vote: bool })

(define-map treasury-withdrawals
    uint
    {
        recipient: principal,
        amount: uint,
        created-height: uint,
        execution-height: uint,
        executed: bool,
        creator: principal
    })

;; Charity Impact Tracking & Donor Recognition Maps
(define-map charities
    uint
    {
        name: (string-ascii 50),
        description: (string-ascii 200),
        wallet-address: principal,
        category: (string-ascii 30),
        verified: bool,
        total-received: uint,
        donor-count: uint,
        created-at: uint
    })

(define-map donations
    uint
    {
        donor: principal,
        charity-id: uint,
        amount: uint,
        timestamp: uint,
        message: (string-ascii 100),
        anonymous: bool
    })

(define-map donor-stats
    principal
    {
        total-donated: uint,
        charity-count: uint,
        first-donation: uint,
        last-donation: uint,
        donation-count: uint
    })

(define-map impact-reports
    uint
    {
        charity-id: uint,
        reporter: principal,
        title: (string-ascii 50),
        description: (string-ascii 300),
        beneficiaries-helped: uint,
        funds-utilized: uint,
        timestamp: uint,
        verified: bool
    })

(define-map donor-badges
    { donor: principal, badge-type: (string-ascii 30) }
    {
        earned-at: uint,
        milestone: uint
    })

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


(define-public (propose-treasury-withdrawal (recipient principal) (amount uint))
    (let
        ((withdrawal-id (+ (var-get withdrawal-count) u1))
         (execution-height (+ stacks-block-height (var-get timelock-duration))))
        (asserts! (not (var-get treasury-paused)) ERR-TREASURY-PAUSED)
(asserts! (<= amount (as-contract (stx-get-balance tx-sender))) ERR-TREASURY-INSUFFICIENT-BALANCE)
        (asserts! (> (get-total-voting-power tx-sender) u0) ERR-NOT-AUTHORIZED)
        (map-set treasury-withdrawals withdrawal-id
            {
                recipient: recipient,
                amount: amount,
                created-height: stacks-block-height,
                execution-height: execution-height,
                executed: false,
                creator: tx-sender
            })
        (var-set withdrawal-count withdrawal-id)
        (ok withdrawal-id)))

(define-public (execute-treasury-withdrawal (withdrawal-id uint))
    (let
        ((withdrawal (unwrap! (map-get? treasury-withdrawals withdrawal-id) ERR-WITHDRAWAL-NOT-FOUND)))
        (asserts! (not (var-get treasury-paused)) ERR-TREASURY-PAUSED)
        (asserts! (not (get executed withdrawal)) ERR-WITHDRAWAL-ALREADY-EXECUTED)
        (asserts! (>= stacks-block-height (get execution-height withdrawal)) ERR-TIMELOCK-NOT-EXPIRED)
(asserts! (<= (get amount withdrawal) (as-contract (stx-get-balance tx-sender))) ERR-TREASURY-INSUFFICIENT-BALANCE)
        (try! (as-contract (stx-transfer? (get amount withdrawal) tx-sender (get recipient withdrawal))))
        (map-set treasury-withdrawals withdrawal-id
            (merge withdrawal {executed: true}))
        (ok true)))

(define-public (set-timelock-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (var-set timelock-duration new-duration)
        (ok true)))

(define-public (pause-treasury)
    (begin
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (var-set treasury-paused true)
        (ok true)))

(define-public (unpause-treasury)
    (begin
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (var-set treasury-paused false)
        (ok true)))

(define-read-only (get-treasury-balance)
    (as-contract (stx-get-balance tx-sender)))

(define-read-only (get-treasury-withdrawal (withdrawal-id uint))
    (map-get? treasury-withdrawals withdrawal-id))

(define-read-only (get-timelock-duration)
    (var-get timelock-duration))

(define-read-only (is-treasury-paused)
    (var-get treasury-paused))

(define-read-only (get-total-withdrawals)
    (var-get withdrawal-count))

;; Governance Metrics and Analytics Functions
(define-read-only (get-governance-stats)
    (let
        (
            (total-props (var-get proposal-count))
            (total-amends (var-get amendment-count))
            (total-withdrawals (var-get withdrawal-count))
        )
        (ok {
            total-proposals: total-props,
            total-amendments: total-amends,
            total-treasury-withdrawals: total-withdrawals,
            current-quorum-threshold: (var-get quorum-threshold),
            min-proposal-duration: (var-get min-proposal-duration),
            timelock-duration: (var-get timelock-duration),
            treasury-balance: (as-contract (stx-get-balance tx-sender)),
            treasury-paused: (var-get treasury-paused)
        })
    )
)

(define-read-only (get-proposal-success-rate)
    (let
        (
            (total-props (var-get proposal-count))
            (passed-count (fold count-passed-proposals (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
        )
        (if (> total-props u0)
            (ok (/ (* passed-count u100) total-props))
            (ok u0)
        )
    )
)

(define-private (count-passed-proposals (proposal-id uint) (acc uint))
    (match (map-get? proposals proposal-id)
        proposal (if (is-eq (get status proposal) "passed")
            (+ acc u1)
            acc
        )
        acc
    )
)

(define-read-only (get-member-voting-stats (member principal))
    (let
        (
            (member-weight (get-member-weight member))
            (voting-power (get-total-voting-power member))
        )
        (ok {
            member: member,
            voting-weight: member-weight,
            total-voting-power: voting-power,
            has-delegation: (is-some (get-delegate member)),
            delegate: (get-delegate member)
        })
    )
)

(define-read-only (get-proposal-participation-rate (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (let
            (
                (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
                (quorum (var-get quorum-threshold))
            )
            (ok {
                proposal-id: proposal-id,
                total-votes: total-votes,
                quorum-threshold: quorum,
                participation-rate: (if (> quorum u0)
                    (/ (* total-votes u100) quorum)
                    u0
                ),
                quorum-met: (>= total-votes quorum)
            })
        )
        (err ERR-PROPOSAL-NOT-FOUND)
    )
)

(define-read-only (analyze-proposal-voting-pattern (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (let
            (
                (yes-votes (get yes-votes proposal))
                (no-votes (get no-votes proposal))
                (total-votes (+ yes-votes no-votes))
            )
            (ok {
                proposal-id: proposal-id,
                yes-votes: yes-votes,
                no-votes: no-votes,
                total-votes: total-votes,
                yes-percentage: (if (> total-votes u0)
                    (/ (* yes-votes u100) total-votes)
                    u0
                ),
                no-percentage: (if (> total-votes u0)
                    (/ (* no-votes u100) total-votes)
                    u0
                ),
                margin: (if (> yes-votes no-votes)
                    (- yes-votes no-votes)
                    (- no-votes yes-votes)
                ),
                outcome: (get status proposal)
            })
        )
        (err ERR-PROPOSAL-NOT-FOUND)
    )
)

(define-read-only (get-active-proposals-count)
    (let
        (
            (total-props (var-get proposal-count))
            (active-count (fold count-active-proposals (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
        )
        (ok active-count)
    )
)

(define-private (count-active-proposals (proposal-id uint) (acc uint))
    (match (map-get? proposals proposal-id)
        proposal (if (is-eq (get status proposal) "active")
            (+ acc u1)
            acc
        )
        acc
    )
)

(define-read-only (get-member-proposal-activity (member principal))
    (let
        (
            (total-props (var-get proposal-count))
            (created-count (fold count-member-proposals-for-user (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) {target-member: member, count: u0}))
        )
        (ok {
            member: member,
            proposals-created: (get count created-count),
            activity-level: (if (>= (get count created-count) u3)
                "high"
                (if (>= (get count created-count) u1)
                    "medium"
                    "low"
                )
            )
        })
    )
)

(define-private (count-member-proposals-for-user (proposal-id uint) (acc {target-member: principal, count: uint}))
    (match (map-get? proposals proposal-id)
        proposal (if (is-eq (get creator proposal) (get target-member acc))
            {target-member: (get target-member acc), count: (+ (get count acc) u1)}
            acc
        )
        acc
    )
)


;; Proposal Search and Utility Functions
(define-read-only (check-proposal-by-status (proposal-id uint) (target-status (string-ascii 20)))
    (match (map-get? proposals proposal-id)
        proposal (ok (is-eq (get status proposal) target-status))
        (err ERR-PROPOSAL-NOT-FOUND)
    )
)

(define-read-only (check-proposal-by-creator (proposal-id uint) (target-creator principal))
    (match (map-get? proposals proposal-id)
        proposal (ok (is-eq (get creator proposal) target-creator))
        (err ERR-PROPOSAL-NOT-FOUND)
    )
)

(define-read-only (check-proposal-voting-threshold (proposal-id uint) (min-votes uint))
    (match (map-get? proposals proposal-id)
        proposal (ok (>= (+ (get yes-votes proposal) (get no-votes proposal)) min-votes))
        (err ERR-PROPOSAL-NOT-FOUND)
    )
)

;; Governance Reputation System
(define-read-only (calculate-member-reputation-score (member principal))
    (let
        (
            (voting-weight (get-member-weight member))
            (proposals-created (unwrap-panic (get-member-proposal-activity member)))
            (member-proposal-count (get proposals-created proposals-created))
            (voting-score (* voting-weight u2))
            (creation-score (* member-proposal-count u10))
            (participation-bonus (if (> voting-weight u0) u25 u0))
        )
        (ok (+ voting-score creation-score participation-bonus))
    )
)

(define-read-only (get-member-governance-profile (member principal))
    (let
        (
            (voting-stats (unwrap-panic (get-member-voting-stats member)))
            (activity-stats (unwrap-panic (get-member-proposal-activity member)))
            (reputation-score (unwrap-panic (calculate-member-reputation-score member)))
        )
        (ok {
            member: member,
            voting-weight: (get voting-weight voting-stats),
            total-voting-power: (get total-voting-power voting-stats),
            has-delegation: (get has-delegation voting-stats),
            proposals-created: (get proposals-created activity-stats),
            activity-level: (get activity-level activity-stats),
            reputation-score: reputation-score,
            governance-tier: (if (>= reputation-score u100)
                "premium"
                (if (>= reputation-score u50)
                    "standard"
                    "basic"
                )
            )
        })
    )
)

(define-read-only (analyze-dao-health)
    (let
        (
            (governance-stats (unwrap-panic (get-governance-stats)))
            (success-rate (unwrap-panic (get-proposal-success-rate)))
            (active-proposals (unwrap-panic (get-active-proposals-count)))
        )
        (ok {
            total-proposals: (get total-proposals governance-stats),
            success-rate: success-rate,
            active-proposals: active-proposals,
            treasury-balance: (get treasury-balance governance-stats),
            quorum-threshold: (get current-quorum-threshold governance-stats),
            health-score: (+ 
                (if (> success-rate u50) u30 u10)
                (if (> active-proposals u0) u20 u5)
                (if (> (get treasury-balance governance-stats) u1000000) u25 u10)
                (if (<= (get current-quorum-threshold governance-stats) u1000) u25 u15)
            ),
            status: (if (> (+ 
                (if (> success-rate u50) u30 u10)
                (if (> active-proposals u0) u20 u5)
                (if (> (get treasury-balance governance-stats) u1000000) u25 u10)
                (if (<= (get current-quorum-threshold governance-stats) u1000) u25 u15)
            ) u75)
                "healthy"
                (if (> (+ 
                    (if (> success-rate u50) u30 u10)
                    (if (> active-proposals u0) u20 u5)
                    (if (> (get treasury-balance governance-stats) u1000000) u25 u10)
                    (if (<= (get current-quorum-threshold governance-stats) u1000) u25 u15)
                ) u50)
                    "moderate"
                    "needs-attention"
                )
            )
        })
    )
)

;; CHARITY IMPACT TRACKING & DONOR RECOGNITION SYSTEM

;; Register a new charity
(define-public (register-charity 
    (name (string-ascii 50))
    (description (string-ascii 200))
    (wallet-address principal)
    (category (string-ascii 30)))
    (let
        ((charity-id (+ (var-get charity-count) u1)))
        (map-set charities charity-id
            {
                name: name,
                description: description,
                wallet-address: wallet-address,
                category: category,
                verified: false,
                total-received: u0,
                donor-count: u0,
                created-at: stacks-block-height
            })
        (var-set charity-count charity-id)
        (ok charity-id)))

;; Verify a charity (only authorized members)
(define-public (verify-charity (charity-id uint))
    (let
        ((charity (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND)))
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (map-set charities charity-id
            (merge charity {verified: true}))
        (ok true)))

;; Record a donation
(define-public (record-donation 
    (charity-id uint)
    (amount uint)
    (message (string-ascii 100))
    (anonymous bool))
    (let
        ((donation-id (+ (var-get donation-count) u1))
         (charity (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND))
         (current-donor-stats (default-to 
            {total-donated: u0, charity-count: u0, first-donation: stacks-block-height, 
             last-donation: stacks-block-height, donation-count: u0}
            (map-get? donor-stats tx-sender)))
         (is-first-time-donor (is-eq (get donation-count current-donor-stats) u0))
         (is-new-charity-for-donor true))
        
        (asserts! (> amount u0) ERR-INVALID-DONATION)
        
        ;; Record the donation
        (map-set donations donation-id
            {
                donor: tx-sender,
                charity-id: charity-id,
                amount: amount,
                timestamp: stacks-block-height,
                message: message,
                anonymous: anonymous
            })
        
        ;; Update charity stats
        (map-set charities charity-id
            (merge charity {
                total-received: (+ (get total-received charity) amount),
                donor-count: (if is-new-charity-for-donor 
                    (+ (get donor-count charity) u1) 
                    (get donor-count charity))
            }))
        
        ;; Update donor stats
        (map-set donor-stats tx-sender
            {
                total-donated: (+ (get total-donated current-donor-stats) amount),
                charity-count: (if is-new-charity-for-donor 
                    (+ (get charity-count current-donor-stats) u1)
                    (get charity-count current-donor-stats)),
                first-donation: (if is-first-time-donor 
                    stacks-block-height 
                    (get first-donation current-donor-stats)),
                last-donation: stacks-block-height,
                donation-count: (+ (get donation-count current-donor-stats) u1)
            })
        
        ;; Update global counters
        (var-set donation-count donation-id)
        (var-set total-donations-tracked (+ (var-get total-donations-tracked) amount))
        
        ;; Check and award badges  
        (unwrap-panic (check-and-award-badges tx-sender (+ (get total-donated current-donor-stats) amount) (+ (get donation-count current-donor-stats) u1)))
        
        (ok donation-id)))

;; Submit impact report
(define-public (submit-impact-report
    (charity-id uint)
    (title (string-ascii 50))
    (description (string-ascii 300))
    (beneficiaries-helped uint)
    (funds-utilized uint))
    (let
        ((report-id (+ (var-get impact-report-count) u1))
         (charity (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND)))
        
        ;; Only charity owner or authorized members can submit reports
        (asserts! (or (is-eq tx-sender (get wallet-address charity)) 
                      (is-eq tx-sender contract-caller)) 
                  ERR-NOT-AUTHORIZED)
        
        (map-set impact-reports report-id
            {
                charity-id: charity-id,
                reporter: tx-sender,
                title: title,
                description: description,
                beneficiaries-helped: beneficiaries-helped,
                funds-utilized: funds-utilized,
                timestamp: stacks-block-height,
                verified: false
            })
        
        (var-set impact-report-count report-id)
        (ok report-id)))

;; Verify impact report
(define-public (verify-impact-report (report-id uint))
    (let
        ((report (unwrap! (map-get? impact-reports report-id) ERR-IMPACT-REPORT-NOT-FOUND)))
        (asserts! (is-eq tx-sender contract-caller) ERR-NOT-AUTHORIZED)
        (map-set impact-reports report-id
            (merge report {verified: true}))
        (ok true)))

;; Check and award badges to donors
(define-private (check-and-award-badges (donor principal) (total-donated uint) (donor-donation-count uint))
    (begin
        ;; First Donor Badge
        (if (and (is-eq donor-donation-count u1) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "first-donor"})))
            (map-set donor-badges {donor: donor, badge-type: "first-donor"}
                {earned-at: stacks-block-height, milestone: u1})
            false)
        
        ;; Generous Giver Badges (based on total donated)
        (if (and (>= total-donated u10000) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "generous-giver-bronze"})))
            (map-set donor-badges {donor: donor, badge-type: "generous-giver-bronze"}
                {earned-at: stacks-block-height, milestone: u10000})
            false)
        
        (if (and (>= total-donated u50000) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "generous-giver-silver"})))
            (map-set donor-badges {donor: donor, badge-type: "generous-giver-silver"}
                {earned-at: stacks-block-height, milestone: u50000})
            false)
        
        (if (and (>= total-donated u100000) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "generous-giver-gold"})))
            (map-set donor-badges {donor: donor, badge-type: "generous-giver-gold"}
                {earned-at: stacks-block-height, milestone: u100000})
            false)
        
        ;; Frequent Donor Badges (based on donation count)
        (if (and (>= donor-donation-count u10) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "frequent-donor-bronze"})))
            (map-set donor-badges {donor: donor, badge-type: "frequent-donor-bronze"}
                {earned-at: stacks-block-height, milestone: u10})
            false)
        
        (if (and (>= donor-donation-count u25) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "frequent-donor-silver"})))
            (map-set donor-badges {donor: donor, badge-type: "frequent-donor-silver"}
                {earned-at: stacks-block-height, milestone: u25})
            false)
        
        (if (and (>= donor-donation-count u50) 
                 (is-none (map-get? donor-badges {donor: donor, badge-type: "frequent-donor-gold"})))
            (map-set donor-badges {donor: donor, badge-type: "frequent-donor-gold"}
                {earned-at: stacks-block-height, milestone: u50})
            false)
        
        (ok true)))

;; Simplified helper functions

;; READ-ONLY FUNCTIONS FOR CHARITY SYSTEM

;; Get charity information
(define-read-only (get-charity (charity-id uint))
    (map-get? charities charity-id))

;; Get donation information
(define-read-only (get-donation (donation-id uint))
    (map-get? donations donation-id))

;; Get donor statistics
(define-read-only (get-donor-stats (donor principal))
    (map-get? donor-stats donor))

;; Get impact report
(define-read-only (get-impact-report (report-id uint))
    (map-get? impact-reports report-id))

;; Get donor badge
(define-read-only (get-donor-badge (donor principal) (badge-type (string-ascii 30)))
    (map-get? donor-badges {donor: donor, badge-type: badge-type}))

;; Get charity leaderboard (simplified for now)
(define-read-only (get-charity-leaderboard)
    (ok (list {id: u1, total-received: u0})))

;; Get donor leaderboard (top 10 by total donated)
(define-read-only (get-donor-leaderboard)
    (ok (list 
        {donor: tx-sender, total-donated: u0, rank: u1}
        ;; Simplified for demo - in practice would iterate through all donors
    )))

;; Get platform statistics
(define-read-only (get-platform-stats)
    (ok {
        total-charities: (var-get charity-count),
        total-donations: (var-get donation-count),
        total-amount-donated: (var-get total-donations-tracked),
        total-impact-reports: (var-get impact-report-count)
    }))

;; Get charity by category (simplified)
(define-read-only (get-charities-by-category (category (string-ascii 30)))
    (ok (list u1)))
