;; Escrow Insurance Pools - Decentralized insurance for escrow protection
;; Users can create and join insurance pools to cover escrow defaults

(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_POOL_NOT_FOUND (err u1001))
(define-constant ERR_INSUFFICIENT_BALANCE (err u1002))
(define-constant ERR_ALREADY_MEMBER (err u1003))
(define-constant ERR_POOL_FULL (err u1004))
(define-constant ERR_MINIMUM_CONTRIBUTION (err u1005))
(define-constant ERR_POOL_INACTIVE (err u1006))
(define-constant ERR_CLAIM_NOT_VALID (err u1007))
(define-constant ERR_ALREADY_CLAIMED (err u1008))
(define-constant ERR_INSUFFICIENT_COVERAGE (err u1009))
(define-constant ERR_INVALID_PREMIUM (err u1010))

;; Data variables
(define-data-var pool-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var default-premium-rate uint u5) ;; 5% of escrow value
(define-data-var minimum-pool-balance uint u1000000) ;; 1 STX minimum

;; Insurance pool storage
(define-map insurance-pools uint {
    pool-name: (string-ascii 50),
    creator: principal,
    total-coverage: uint,
    available-balance: uint,
    member-count: uint,
    max-members: uint,
    min-contribution: uint,
    risk-tier: uint, ;; 1=low, 2=medium, 3=high
    premium-rate: uint, ;; basis points
    is-active: bool,
    created-at: uint,
    claims-paid: uint
})

;; Pool membership tracking
(define-map pool-members {pool-id: uint, member: principal} {
    contribution-amount: uint,
    join-height: uint,
    share-percentage: uint,
    claims-received: uint,
    is-active: bool
})

;; Track member's pools
(define-map member-pools {member: principal} {
    pool-ids: (list 20 uint)
})

;; Insurance policies for specific escrows
(define-map escrow-policies {escrow-id: uint} {
    pool-id: uint,
    insured-amount: uint,
    premium-paid: uint,
    policy-holder: principal,
    coverage-start: uint,
    coverage-end: uint,
    is-active: bool
})

;; Insurance claims
(define-map insurance-claims uint {
    claim-type: (string-ascii 20), ;; "DEFAULT", "DISPUTE", "FRAUD"
    escrow-id: uint,
    pool-id: uint,
    claimant: principal,
    claim-amount: uint,
    evidence-hash: (buff 32),
    claim-status: (string-ascii 15), ;; "PENDING", "APPROVED", "REJECTED"
    submit-height: uint,
    resolve-height: uint,
    approved-amount: uint
})

;; Create a new insurance pool
(define-public (create-insurance-pool
    (pool-name (string-ascii 50))
    (max-members uint)
    (min-contribution uint)
    (risk-tier uint)
    (premium-rate uint))
    (let ((pool-id (var-get pool-counter)))
        (begin
            (asserts! (> max-members u0) ERR_UNAUTHORIZED)
            (asserts! (> min-contribution u0) ERR_MINIMUM_CONTRIBUTION)
            (asserts! (and (>= risk-tier u1) (<= risk-tier u3)) ERR_UNAUTHORIZED)
            (asserts! (and (>= premium-rate u1) (<= premium-rate u50)) ERR_INVALID_PREMIUM) ;; 0.01% to 5%
            (map-set insurance-pools pool-id {
                pool-name: pool-name,
                creator: tx-sender,
                total-coverage: u0,
                available-balance: u0,
                member-count: u0,
                max-members: max-members,
                min-contribution: min-contribution,
                risk-tier: risk-tier,
                premium-rate: premium-rate,
                is-active: true,
                created-at: stacks-block-height,
                claims-paid: u0
            })
            (var-set pool-counter (+ pool-id u1))
            (ok pool-id))))

;; Join an insurance pool as a coverage provider
(define-public (join-insurance-pool (pool-id uint) (contribution-amount uint))
    (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR_POOL_NOT_FOUND))
          (existing-member (map-get? pool-members {pool-id: pool-id, member: tx-sender})))
        (begin
            (asserts! (get is-active pool) ERR_POOL_INACTIVE)
            (asserts! (is-none existing-member) ERR_ALREADY_MEMBER)
            (asserts! (< (get member-count pool) (get max-members pool)) ERR_POOL_FULL)
            (asserts! (>= contribution-amount (get min-contribution pool)) ERR_MINIMUM_CONTRIBUTION)
            (asserts! (>= (stx-get-balance tx-sender) contribution-amount) ERR_INSUFFICIENT_BALANCE)
            
            (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
            
            (let ((new-total-coverage (+ (get total-coverage pool) contribution-amount))
                  (share-percentage (/ (* contribution-amount u10000) new-total-coverage)))
                (map-set pool-members {pool-id: pool-id, member: tx-sender} {
                    contribution-amount: contribution-amount,
                    join-height: stacks-block-height,
                    share-percentage: share-percentage,
                    claims-received: u0,
                    is-active: true
                })
                
                (map-set insurance-pools pool-id (merge pool {
                    total-coverage: new-total-coverage,
                    available-balance: (+ (get available-balance pool) contribution-amount),
                    member-count: (+ (get member-count pool) u1)
                }))
                
                ;; Update member's pool list
                (let ((current-pools (default-to {pool-ids: (list)} (map-get? member-pools {member: tx-sender}))))
                    (map-set member-pools {member: tx-sender} {
                        pool-ids: (unwrap! (as-max-len? (append (get pool-ids current-pools) pool-id) u20) ERR_UNAUTHORIZED)
                    }))
                
                (ok true)))))

;; Purchase insurance for an escrow
(define-public (insure-escrow
    (escrow-id uint)
    (pool-id uint)
    (insured-amount uint)
    (coverage-duration uint))
    (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR_POOL_NOT_FOUND))
          (premium (/ (* insured-amount (get premium-rate pool)) u10000)))
        (begin
            (asserts! (get is-active pool) ERR_POOL_INACTIVE)
            (asserts! (>= (get available-balance pool) insured-amount) ERR_INSUFFICIENT_COVERAGE)
            (asserts! (>= (stx-get-balance tx-sender) premium) ERR_INSUFFICIENT_BALANCE)
            (asserts! (> coverage-duration u0) ERR_UNAUTHORIZED)
            
            (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
            
            (map-set escrow-policies {escrow-id: escrow-id} {
                pool-id: pool-id,
                insured-amount: insured-amount,
                premium-paid: premium,
                policy-holder: tx-sender,
                coverage-start: stacks-block-height,
                coverage-end: (+ stacks-block-height coverage-duration),
                is-active: true
            })
            
            ;; Update pool balance (reserve coverage amount)
            (map-set insurance-pools pool-id (merge pool {
                available-balance: (- (get available-balance pool) insured-amount)
            }))
            
            (ok true))))

;; Submit insurance claim
(define-public (submit-insurance-claim
    (claim-type (string-ascii 20))
    (escrow-id uint)
    (claim-amount uint)
    (evidence-hash (buff 32)))
    (let ((policy (unwrap! (map-get? escrow-policies {escrow-id: escrow-id}) ERR_CLAIM_NOT_VALID))
          (claim-id (var-get claim-counter)))
        (begin
            (asserts! (is-eq tx-sender (get policy-holder policy)) ERR_UNAUTHORIZED)
            (asserts! (get is-active policy) ERR_CLAIM_NOT_VALID)
            (asserts! (<= stacks-block-height (get coverage-end policy)) ERR_CLAIM_NOT_VALID)
            (asserts! (<= claim-amount (get insured-amount policy)) ERR_CLAIM_NOT_VALID)
            
            (map-set insurance-claims claim-id {
                claim-type: claim-type,
                escrow-id: escrow-id,
                pool-id: (get pool-id policy),
                claimant: tx-sender,
                claim-amount: claim-amount,
                evidence-hash: evidence-hash,
                claim-status: "PENDING",
                submit-height: stacks-block-height,
                resolve-height: u0,
                approved-amount: u0
            })
            
            (var-set claim-counter (+ claim-id u1))
            (ok claim-id))))

;; Approve insurance claim (simplified - in production would need governance)
(define-public (approve-claim (claim-id uint) (approved-amount uint))
    (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_VALID))
          (pool (unwrap! (map-get? insurance-pools (get pool-id claim)) ERR_POOL_NOT_FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get creator pool)) ERR_UNAUTHORIZED) ;; Simplified - pool creator can approve
            (asserts! (is-eq (get claim-status claim) "PENDING") ERR_ALREADY_CLAIMED)
            (asserts! (<= approved-amount (get claim-amount claim)) ERR_CLAIM_NOT_VALID)
            (asserts! (>= (get total-coverage pool) approved-amount) ERR_INSUFFICIENT_COVERAGE)
            
            ;; Pay out claim
            (try! (as-contract (stx-transfer? approved-amount tx-sender (get claimant claim))))
            
            ;; Update claim status
            (map-set insurance-claims claim-id (merge claim {
                claim-status: "APPROVED",
                resolve-height: stacks-block-height,
                approved-amount: approved-amount
            }))
            
            ;; Update pool statistics
            (map-set insurance-pools (get pool-id claim) (merge pool {
                total-coverage: (- (get total-coverage pool) approved-amount),
                claims-paid: (+ (get claims-paid pool) approved-amount)
            }))
            
            (ok true))))

;; Distribute premium earnings to pool members
(define-public (distribute-earnings (pool-id uint))
    (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR_POOL_NOT_FOUND)))
        (begin
            (asserts! (get is-active pool) ERR_POOL_INACTIVE)
            ;; Simplified distribution - in production would iterate through all members
            (ok true))))

;; Withdraw from insurance pool
(define-public (withdraw-from-pool (pool-id uint) (withdrawal-amount uint))
    (let ((pool (unwrap! (map-get? insurance-pools pool-id) ERR_POOL_NOT_FOUND))
          (member-info (unwrap! (map-get? pool-members {pool-id: pool-id, member: tx-sender}) ERR_UNAUTHORIZED)))
        (begin
            (asserts! (get is-active member-info) ERR_UNAUTHORIZED)
            (asserts! (<= withdrawal-amount (get contribution-amount member-info)) ERR_INSUFFICIENT_BALANCE)
            (asserts! (>= (get available-balance pool) withdrawal-amount) ERR_INSUFFICIENT_BALANCE)
            
            (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
            
            ;; Update member info
            (map-set pool-members {pool-id: pool-id, member: tx-sender} (merge member-info {
                contribution-amount: (- (get contribution-amount member-info) withdrawal-amount)
            }))
            
            ;; Update pool
            (map-set insurance-pools pool-id (merge pool {
                total-coverage: (- (get total-coverage pool) withdrawal-amount),
                available-balance: (- (get available-balance pool) withdrawal-amount)
            }))
            
            (ok true))))

;; Read-only functions
(define-read-only (get-pool-info (pool-id uint))
    (map-get? insurance-pools pool-id))

(define-read-only (get-member-info (pool-id uint) (member principal))
    (map-get? pool-members {pool-id: pool-id, member: member}))

(define-read-only (get-policy-info (escrow-id uint))
    (map-get? escrow-policies {escrow-id: escrow-id}))

(define-read-only (get-claim-info (claim-id uint))
    (map-get? insurance-claims claim-id))

(define-read-only (calculate-premium (pool-id uint) (insured-amount uint))
    (match (map-get? insurance-pools pool-id)
        pool (ok (/ (* insured-amount (get premium-rate pool)) u10000))
        ERR_POOL_NOT_FOUND))

(define-read-only (get-pool-capacity (pool-id uint))
    (match (map-get? insurance-pools pool-id)
        pool (ok {
            total-coverage: (get total-coverage pool),
            available-balance: (get available-balance pool),
            utilization-rate: (if (> (get total-coverage pool) u0)
                                (/ (* (- (get total-coverage pool) (get available-balance pool)) u100)
                                   (get total-coverage pool))
                                u0)
        })
        ERR_POOL_NOT_FOUND))
