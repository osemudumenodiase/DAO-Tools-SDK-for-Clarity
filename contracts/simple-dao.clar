;; Simple DAO with Basic Donation Tracking

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u106))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u107))
(define-constant ERR-INVALID-AMOUNT (err u109))
(define-constant ERR-CAMPAIGN-NOT-FOUND (err u110))
(define-constant ERR-INVALID-CAMPAIGN (err u111))
(define-constant ERR-CAMPAIGN-EXPIRED (err u112))

(define-data-var proposal-count uint u0)
(define-data-var donation-count uint u0)
(define-data-var total-donations uint u0)
(define-data-var campaign-count uint u0)

(define-map proposals
    uint 
    {
        creator: principal,
        title: (string-ascii 50),
        description: (string-ascii 200),
        start-height: uint,
        end-height: uint,
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20)
    }
)

(define-map votes 
    { proposal-id: uint, voter: principal } 
    { vote: bool }
)

(define-map donations
    uint
    {
        donor: principal,
        recipient: principal,
        amount: uint,
        timestamp: uint,
        message: (string-ascii 100)
    }
)

(define-map donor-totals
    principal
    uint
)

;; Campaign System Maps
(define-map campaigns
    uint
    {
        title: (string-ascii 50),
        description: (string-ascii 150),
        funding-goal: uint,
        current-funds: uint,
        end-height: uint,
        creator: principal,
        status: (string-ascii 20)
    })

(define-map campaign-contributors
    { campaign-id: uint, contributor: principal }
    uint
)

(define-public (create-proposal 
    (title (string-ascii 50))
    (description (string-ascii 200))
    (duration uint))
    (let
        ((proposal-id (+ (var-get proposal-count) u1))
         (start-block stacks-block-height)
         (end-block (+ start-block duration)))
        (map-set proposals proposal-id
            {
                creator: tx-sender,
                title: title,
                description: description,
                start-height: start-block,
                end-height: end-block,
                yes-votes: u0,
                no-votes: u0,
                status: "active"
            })
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

(define-public (cast-vote (proposal-id uint) (vote bool))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
        (asserts! (is-eq (get status proposal) "active") ERR-PROPOSAL-NOT-ACTIVE)
        (asserts! (<= stacks-block-height (get end-height proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
        
        (map-set votes {proposal-id: proposal-id, voter: tx-sender} {vote: vote})
        (if vote
            (map-set proposals proposal-id 
                (merge proposal {yes-votes: (+ (get yes-votes proposal) u1)}))
            (map-set proposals proposal-id 
                (merge proposal {no-votes: (+ (get no-votes proposal) u1)})))
        (ok true)
    )
)

(define-public (record-donation 
    (recipient principal)
    (amount uint)
    (message (string-ascii 100)))
    (let
        ((donation-id (+ (var-get donation-count) u1))
         (current-total (default-to u0 (map-get? donor-totals tx-sender))))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (map-set donations donation-id
            {
                donor: tx-sender,
                recipient: recipient,
                amount: amount,
                timestamp: stacks-block-height,
                message: message
            })
        
        (map-set donor-totals tx-sender (+ current-total amount))
        (var-set donation-count donation-id)
        (var-set total-donations (+ (var-get total-donations) amount))
        
        (ok donation-id)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-donation (donation-id uint))
    (map-get? donations donation-id)
)

(define-read-only (get-donor-total (donor principal))
    (default-to u0 (map-get? donor-totals donor))
)

(define-read-only (get-stats)
    (ok {
        total-proposals: (var-get proposal-count),
        total-donations-count: (var-get donation-count),
        total-donation-amount: (var-get total-donations),
        total-campaigns: (var-get campaign-count)
    })
)

;; MILESTONE-BASED CHARITY CAMPAIGNS

;; Create a milestone-based fundraising campaign
(define-public (create-campaign
    (title (string-ascii 50))
    (description (string-ascii 150))
    (funding-goal uint)
    (duration uint))
    (let
        ((campaign-id (+ (var-get campaign-count) u1))
         (end-height (+ stacks-block-height duration)))
        
        (asserts! (> funding-goal u0) ERR-INVALID-CAMPAIGN)
        (asserts! (> duration u144) ERR-INVALID-CAMPAIGN)  ;; Minimum 1 day
        
        (map-set campaigns campaign-id
            {
                title: title,
                description: description,
                funding-goal: funding-goal,
                current-funds: u0,
                end-height: end-height,
                creator: tx-sender,
                status: "active"
            })
        
        (var-set campaign-count campaign-id)
        (ok campaign-id)
    )
)

;; Contribute to a campaign
(define-public (contribute-to-campaign (campaign-id uint) (amount uint))
    (let
        ((campaign (unwrap! (map-get? campaigns campaign-id) ERR-CAMPAIGN-NOT-FOUND))
         (current-contribution (default-to u0 (map-get? campaign-contributors {campaign-id: campaign-id, contributor: tx-sender})))
         (new-total-funds (+ (get current-funds campaign) amount)))
        
        (asserts! (is-eq (get status campaign) "active") ERR-CAMPAIGN-EXPIRED)
        (asserts! (<= stacks-block-height (get end-height campaign)) ERR-CAMPAIGN-EXPIRED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Update campaign funds
        (map-set campaigns campaign-id
            (merge campaign {
                current-funds: new-total-funds,
                status: (if (>= new-total-funds (get funding-goal campaign)) "completed" "active")
            }))
        
        ;; Update contributor amount
        (map-set campaign-contributors {campaign-id: campaign-id, contributor: tx-sender}
            (+ current-contribution amount))
        
        (ok amount)
    )
)

;; Get campaign details
(define-read-only (get-campaign (campaign-id uint))
    (map-get? campaigns campaign-id)
)

;; Get campaign progress with analytics
(define-read-only (get-campaign-progress (campaign-id uint))
    (match (map-get? campaigns campaign-id)
        campaign (let
            ((progress-percentage (if (> (get funding-goal campaign) u0)
                (/ (* (get current-funds campaign) u100) (get funding-goal campaign))
                u0))
             (time-remaining (if (> (get end-height campaign) stacks-block-height)
                (- (get end-height campaign) stacks-block-height)
                u0)))
            (ok {
                campaign-id: campaign-id,
                title: (get title campaign),
                current-funds: (get current-funds campaign),
                funding-goal: (get funding-goal campaign),
                progress-percentage: progress-percentage,
                time-remaining: time-remaining,
                status: (get status campaign),
                creator: (get creator campaign)
            }))
        (err ERR-CAMPAIGN-NOT-FOUND)
    )
)

;; Get contributor's contribution to a campaign
(define-read-only (get-campaign-contribution (campaign-id uint) (contributor principal))
    (default-to u0 (map-get? campaign-contributors {campaign-id: campaign-id, contributor: contributor}))
)
