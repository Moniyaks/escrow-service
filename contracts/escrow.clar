(define-data-var buyer principal tx-sender)
(define-data-var seller principal tx-sender)
(define-data-var arbitrator principal tx-sender)
(define-data-var amount uint u0)
(define-data-var is-complete bool false)
(define-data-var is-disputed bool false)
(define-data-var escrow-status (string-ascii 20) "PENDING")
(define-data-var expiration-height uint u0)
(define-constant ESCROW_DURATION u1440) ;; ~10 days in blocks
(define-data-var currency-type (string-ascii 10) "STX")

;; Buyer initiates the escrow by locking funds
(define-public (initiate-escrow 
    (seller-principal principal) 
    (arbitrator-principal principal) 
    (escrow-amount uint)
    (currency (string-ascii 10)))
  (begin
    (asserts! (is-eq tx-sender (var-get buyer)) (err u100))
    (asserts! (> escrow-amount u0) (err u106))
    (asserts! (>= (stx-get-balance tx-sender) escrow-amount) (err u101))
    (asserts! (not (is-eq seller-principal tx-sender)) (err u107))
    (asserts! (not (is-eq arbitrator-principal tx-sender)) (err u108))
    (asserts! (not (is-eq seller-principal arbitrator-principal)) (err u109))
    (try! (stx-transfer? escrow-amount tx-sender (as-contract tx-sender)))
    (var-set seller seller-principal)
    (var-set arbitrator arbitrator-principal)
    (var-set amount escrow-amount)
    (var-set expiration-height (+ block-height ESCROW_DURATION))
    (var-set currency-type currency)
    (var-set escrow-status "ACTIVE")
    (ok true)
  )
)

;; Seller confirms delivery, allowing fund release
(define-public (confirm-delivery)
  (begin
    (asserts! (is-eq tx-sender (var-get seller)) (err u102))
    (asserts! (not (var-get is-disputed)) (err u103))
    (var-set is-complete true)
    (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get seller)))
    (var-set escrow-status "COMPLETED")
    (ok true)
  )
)

;; Buyer raises a dispute, involving the arbitrator
(define-public (raise-dispute)
  (begin
    (asserts! (is-eq tx-sender (var-get buyer)) (err u104))
    (var-set is-disputed true)
    (ok true)
  )
)

;; Arbitrator resolves the dispute in favor of either party
(define-public (resolve-dispute (refund-buyer bool))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u105))
    (if refund-buyer
      (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get buyer)))
      (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get seller)))
    )
    (var-set is-complete true)
    (ok true)
  )
)


;; New function for partial refund resolution
(define-public (resolve-partial 
    (buyer-amount uint) 
    (seller-amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u105))
    (asserts! (is-eq (+ buyer-amount seller-amount) (var-get amount)) (err u113))
    (try! (stx-transfer? buyer-amount (as-contract tx-sender) (var-get buyer)))
    (try! (stx-transfer? seller-amount (as-contract tx-sender) (var-get seller)))
    (var-set is-complete true)
    (ok true)))


;; Add to data vars
(define-data-var require-multi-sig bool false)
(define-data-var multi-sig-threshold uint u1000000) ;; Example: 1M uSTX
(define-data-var arbitrator-approved bool false)
(define-data-var total-amount uint u0)

;; New arbitrator approval function
(define-public (approve-high-value-release)
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u105))
    (asserts! (var-get require-multi-sig) (err u114))
    (var-set arbitrator-approved true)
    (ok true)))


(define-map user-ratings principal 
  {
    positive-ratings: uint,
    negative-ratings: uint,
    total-transactions: uint
  })

(define-public (rate-counterparty (target-principal principal) (is-positive bool))
  (begin 
    (asserts! (or (is-eq tx-sender (var-get buyer)) (is-eq tx-sender (var-get seller))) (err u120))
    (asserts! (var-get is-complete) (err u121))
    (match (map-get? user-ratings target-principal)
      existing-rating 
        (map-set user-ratings target-principal
          {
            positive-ratings: (if is-positive (+ (get positive-ratings existing-rating) u1) (get positive-ratings existing-rating)),
            negative-ratings: (if is-positive (get negative-ratings existing-rating) (+ (get negative-ratings existing-rating) u1)),
            total-transactions: (+ (get total-transactions existing-rating) u1)
          })
      (map-set user-ratings target-principal 
        {
          positive-ratings: (if is-positive u1 u0),
          negative-ratings: (if is-positive u0 u1),
          total-transactions: u1
        }))
    (ok true)))



    (define-map milestones uint 
  {
    amount: uint,
    description: (string-ascii 64),
    is-complete: bool
  })

(define-data-var milestone-count uint u0)

(define-public (add-milestone (milestone-amount uint) (description (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get seller)) (err u130))
    (asserts! (<= (+ milestone-amount (var-get amount)) (var-get total-amount)) (err u131))
    (map-set milestones (var-get milestone-count)
      {
        amount: milestone-amount,
        description: description,
        is-complete: false
      })
    (var-set milestone-count (+ (var-get milestone-count) u1))
    (ok true)))

(define-public (complete-milestone (milestone-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get buyer)) (err u132))
    (match (map-get? milestones milestone-id)
      milestone (begin
        (try! (stx-transfer? (get amount milestone) (as-contract tx-sender) (var-get seller)))
        (map-set milestones milestone-id
          (merge milestone { is-complete: true }))
        (ok true))
      (err u133))))


(define-data-var arbitrator-fee-percentage uint u2) ;; 2% fee
(define-map arbitrator-earnings principal uint)

(define-public (set-arbitrator-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u140))
    (asserts! (<= new-fee u10) (err u141)) ;; Max 10% fee
    (var-set arbitrator-fee-percentage new-fee)
    (ok true)))

(define-public (claim-arbitrator-fees)
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u142))
    (match (map-get? arbitrator-earnings tx-sender)
      earned (begin
        (try! (stx-transfer? earned (as-contract tx-sender) tx-sender))
        (map-set arbitrator-earnings tx-sender u0)
        (ok true))
      (err u143))))


;; New timeout claim function
(define-public (claim-timeout)
  (begin
    (asserts! (> block-height (var-get expiration-height)) (err u150))
    (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get buyer)))
    (var-set escrow-status "EXPIRED")
    (ok true)))


;; Add at the top
(define-trait escrow-events
  ((escrow-initiated (principal principal uint) (response bool uint))
   (delivery-confirmed (principal) (response bool uint))
   (dispute-raised (principal) (response bool uint))))

;; Emit in relevant functions
(print {event: "escrow-initiated", buyer: tx-sender, seller: (var-get seller) , amount: (var-get amount)})



(define-map escrow-history uint 
  {
    buyer: principal,
    seller: principal,
    amount: uint,
    status: (string-ascii 20),
    timestamp: uint
  })

(define-data-var escrow-count uint u0)

;; Add to initiate-escrow
(map-set escrow-history (var-get escrow-count)
  {
    buyer: tx-sender,
    seller: (var-get seller),
    amount: (var-get amount),
    status: "ACTIVE",
    timestamp: block-height
  })
(var-set escrow-count (+ (var-get escrow-count) u1))


;; Insurance pool functionality
(define-data-var insurance-pool-balance uint u0)
(define-constant INSURANCE_FEE_PERCENTAGE u1) ;; 1%

(define-public (add-insurance)
  (begin
    (asserts! (is-eq tx-sender (var-get buyer)) (err u160))
    (let ((insurance-fee (/ (* (var-get amount) INSURANCE_FEE_PERCENTAGE) u100)))
      (try! (stx-transfer? insurance-fee tx-sender (as-contract tx-sender)))
      (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) insurance-fee))
      (ok true))))

(define-public (claim-insurance)
  (begin
    (asserts! (var-get is-disputed) (err u161))
    (asserts! (is-eq tx-sender (var-get buyer)) (err u162))
    (try! (stx-transfer? (var-get amount) (as-contract tx-sender) tx-sender))
    (ok true)))


(define-map user-transaction-volume principal uint)
(define-constant TIER1-THRESHOLD u1000000) ;; 1M uSTX
(define-constant TIER2-THRESHOLD u5000000) ;; 5M uSTX

(define-public (calculate-fee (user-principal principal))
  (begin
    (match (map-get? user-transaction-volume user-principal)
      volume (ok (if (> volume TIER2-THRESHOLD)
                    u1 ;; 1% fee
                    (if (> volume TIER1-THRESHOLD)
                        u2 ;; 2% fee
                        u3))) ;; 3% fee
      (ok u3)))) ;; Default 3% fee


(define-map time-locks uint 
  {
    release-height: uint,
    amount: uint,
    recipient: principal
  })

(define-data-var time-lock-count uint u0)

(define-public (create-time-lock (blocks uint) (lock-amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get seller)) (err u170))
    (asserts! (<= lock-amount (var-get amount)) (err u171))
    (map-set time-locks (var-get time-lock-count)
      {
        release-height: (+ block-height blocks),
        amount: lock-amount,
        recipient: (var-get seller)
      })
    (var-set time-lock-count (+ (var-get time-lock-count) u1))
    (ok true)))

(define-public (execute-time-lock (lock-id uint))
  (begin
    (match (map-get? time-locks lock-id)
      lock (begin
        (asserts! (>= block-height (get release-height lock)) (err u172))
        (try! (stx-transfer? (get amount lock) 
                            (as-contract tx-sender) 
                            (get recipient lock)))
        (ok true))
      (err u173))))


;; Add supported currencies map
(define-map supported-currencies (string-ascii 10) bool)

;; Initialize supported currencies
(map-set supported-currencies "STX" true)
(map-set supported-currencies "BTC" true)

(define-public (add-currency (currency-symbol (string-ascii 10)))
  (begin 
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u180))
    (map-set supported-currencies currency-symbol true)
    (ok true)))





(define-data-var cancellation-window uint u100) ;; blocks
(define-data-var can-cancel bool true)

(define-public (cancel-escrow)
  (begin
    (asserts! (is-eq tx-sender (var-get buyer)) (err u181))
    (asserts! (var-get can-cancel) (err u182))
    (asserts! (< block-height (+ (var-get cancellation-window) block-height)) (err u183))
    (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get buyer)))
    (var-set escrow-status "CANCELLED")
    (ok true)))





      
(define-map referrers principal uint)
(define-constant REFERRAL_REWARD u1) ;; 1%

(define-public (add-referrer (referrer principal))
  (begin
    (asserts! (not (is-eq referrer tx-sender)) (err u184))
    (let ((reward (/ (* (var-get amount) REFERRAL_REWARD) u100)))
      (try! (stx-transfer? reward (as-contract tx-sender) referrer))
      (map-set referrers referrer (+ (default-to u0 (map-get? referrers referrer)) reward))
      (ok true))))



(define-map whitelisted-users principal bool)

(define-public (add-to-whitelist (user principal))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u185))
    (map-set whitelisted-users user true)
    (ok true)))

(define-public (remove-from-whitelist (user principal))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u186))
    (map-set whitelisted-users user false)
    (ok true)))



(define-map escrow-participants principal bool)
(define-data-var required-confirmations uint u0)
(define-map participant-confirmations principal bool)

(define-public (add-participant (participant principal))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u187))
    (map-set escrow-participants participant true)
    (var-set required-confirmations (+ (var-get required-confirmations) u1))
    (ok true)))



(define-data-var is-paused bool false)
(define-data-var admin principal tx-sender)

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u188))
    (var-set is-paused (not (var-get is-paused)))
    (ok true)))



(define-map transaction-comments uint (string-ascii 500))
(define-data-var comment-count uint u0)

(define-public (add-comment (comment (string-ascii 500)))
  (begin
    (asserts! (or (is-eq tx-sender (var-get buyer)) 
                  (is-eq tx-sender (var-get seller))) 
              (err u190))
    (map-set transaction-comments (var-get comment-count) comment)
    (var-set comment-count (+ (var-get comment-count) u1))
    (ok true)))









(define-data-var auto-release-height uint u0)
(define-constant AUTO_RELEASE_BLOCKS u2880) ;; ~20 days

(define-public (set-auto-release)
  (begin
    (asserts! (is-eq tx-sender (var-get seller)) (err u200))
    (var-set auto-release-height (+ block-height AUTO_RELEASE_BLOCKS))
    (ok true)))

(define-public (auto-release)
  (begin
    (asserts! (>= block-height (var-get auto-release-height)) (err u201))
    (try! (stx-transfer? (var-get amount) (as-contract tx-sender) (var-get seller)))
    (var-set escrow-status "AUTO_RELEASED")
    (ok true)))


(define-map backup-arbitrators principal bool)
(define-data-var active-arbitrator-count uint u0)

(define-public (add-backup-arbitrator (new-arbitrator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u210))
    (map-set backup-arbitrators new-arbitrator true)
    (var-set active-arbitrator-count (+ (var-get active-arbitrator-count) u1))
    (ok true)))



(define-map payment-splits principal uint)

(define-public (set-payment-split (recipient principal) (percentage uint))
  (begin
    (asserts! (is-eq tx-sender (var-get seller)) (err u220))
    (asserts! (<= percentage u100) (err u221))
    (map-set payment-splits recipient percentage)
    (ok true)))



(define-map user-reputation principal uint)
(define-constant BASE_FEE u30) ;; 3%
(define-constant MIN_FEE u10) ;; 1%

(define-public (calculate-reputation-fee (user principal))
  (begin
    (let ((reputation (default-to u0 (map-get? user-reputation user))))
      (ok (if (> (- BASE_FEE reputation) MIN_FEE)
              (- BASE_FEE reputation)
              MIN_FEE)))))


(define-data-var emergency-admin principal tx-sender)
(define-data-var is-emergency bool false)

(define-public (toggle-emergency)
  (begin
    (asserts! (is-eq tx-sender (var-get emergency-admin)) (err u230))
    (var-set is-emergency (not (var-get is-emergency)))
    (ok true)))



(define-map exchange-rates (string-ascii 10) uint)

(define-public (set-exchange-rate (currency (string-ascii 10)) (rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get arbitrator)) (err u240))
    (map-set exchange-rates currency rate)
    (ok true)))


(define-map activity-log uint 
  {
    action: (string-ascii 20),
    actor: principal,
    timestamp: uint
  })
(define-data-var log-count uint u0)

(define-public (log-activity (action (string-ascii 20)))
  (begin
    (map-set activity-log (var-get log-count)
      {
        action: action,
        actor: tx-sender,
        timestamp: block-height
      })
    (var-set log-count (+ (var-get log-count) u1))
    (ok true)))









(define-map installment-plans uint {
  total-installments: uint,
  current-installment: uint,
  amount-per-installment: uint,
  interval-blocks: uint,
  next-payment-height: uint,
  buyer: principal,
  seller: principal
})

(define-data-var installment-plan-counter uint u0)

(define-public (create-installment-plan 
    (seller-principal principal) 
    (total-installments uint)
    (amount-per-installment uint)
    (interval-blocks uint))
  (let ((plan-id (var-get installment-plan-counter)))
    (begin
      (asserts! (> total-installments u0) (err u500))
      (asserts! (> amount-per-installment u0) (err u501))
      (asserts! (> interval-blocks u0) (err u502))
      (try! (stx-transfer? amount-per-installment tx-sender (as-contract tx-sender)))
      (map-set installment-plans plan-id {
        total-installments: total-installments,
        current-installment: u1,
        amount-per-installment: amount-per-installment,
        interval-blocks: interval-blocks,
        next-payment-height: (+ block-height interval-blocks),
        buyer: tx-sender,
        seller: seller-principal
      })
      (var-set installment-plan-counter (+ plan-id u1))
      (ok plan-id)
    )
  )
)

(define-public (pay-next-installment (plan-id uint))
  (let ((plan (unwrap! (map-get? installment-plans plan-id) (err u503))))
    (begin
      (asserts! (is-eq tx-sender (get buyer plan)) (err u504))
      (asserts! (< (get current-installment plan) (get total-installments plan)) (err u505))
      (try! (stx-transfer? (get amount-per-installment plan) tx-sender (as-contract tx-sender)))
      (map-set installment-plans plan-id (merge plan {
        current-installment: (+ (get current-installment plan) u1),
        next-payment-height: (+ block-height (get interval-blocks plan))
      }))
      (ok true)
    )
  )
)

(define-public (release-installment (plan-id uint))
  (let ((plan (unwrap! (map-get? installment-plans plan-id) (err u503))))
    (begin
      (asserts! (is-eq tx-sender (get seller plan)) (err u506))
      (try! (as-contract (stx-transfer? (get amount-per-installment plan) tx-sender (get seller plan))))
      (ok true)
    )
  )
)




(define-map escrows uint {
  buyer: principal,
  seller: principal,
  arbitrator: principal,
  amount: uint,
  currency-type: (string-ascii 10),
  is-complete: bool,
  is-disputed: bool,
  escrow-status: (string-ascii 20),
  expiration-height: uint
})

(define-data-var escrow-id-counter uint u0)

(define-public (create-escrow 
    (seller-principal principal) 
    (arbitrator-principal principal) 
    (escrow-amount uint)
    (currency (string-ascii 10)))
  (let ((new-escrow-id (var-get escrow-id-counter)))
    (begin
      (asserts! (> escrow-amount u0) (err u106))
      (asserts! (>= (stx-get-balance tx-sender) escrow-amount) (err u101))
      (asserts! (not (is-eq seller-principal tx-sender)) (err u107))
      (asserts! (not (is-eq arbitrator-principal tx-sender)) (err u108))
      (asserts! (not (is-eq seller-principal arbitrator-principal)) (err u109))
      (try! (stx-transfer? escrow-amount tx-sender (as-contract tx-sender)))
      (map-set escrows new-escrow-id {
        buyer: tx-sender,
        seller: seller-principal,
        arbitrator: arbitrator-principal,
        amount: escrow-amount,
        currency-type: currency,
        is-complete: false,
        is-disputed: false,
        escrow-status: "ACTIVE",
        expiration-height: (+ block-height ESCROW_DURATION)
      })
      (var-set escrow-id-counter (+ new-escrow-id u1))
      (ok new-escrow-id)
    )
  )
)

(define-public (complete-escrow (escrow-id uint))
  (let ((escrow (unwrap! (map-get? escrows escrow-id) (err u400))))
    (begin
      (asserts! (is-eq tx-sender (get seller escrow)) (err u102))
      (asserts! (not (get is-disputed escrow)) (err u103))
      (try! (stx-transfer? (get amount escrow) (as-contract tx-sender) (get seller escrow)))
      (map-set escrows escrow-id (merge escrow {
        is-complete: true,
        escrow-status: "COMPLETED"
      }))
      (ok true)
    )
  )
)



(define-trait ft-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
    (get-decimals () (response uint uint))
  )
)

(define-map supported-tokens (string-ascii 10) principal)

(define-public (add-supported-token (token-symbol (string-ascii 10)) (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u300))
    (map-set supported-tokens token-symbol token-contract)
    (ok true)
  )
)

(define-public (initiate-token-escrow 
    (seller-principal principal) 
    (arbitrator-principal principal) 
    (escrow-amount uint)
    (token-symbol (string-ascii 10)))
  (let ((token-contract (unwrap! (map-get? supported-tokens token-symbol) (err u301))))
    (begin
      (asserts! (is-eq tx-sender (var-get buyer)) (err u100))
      (asserts! (> escrow-amount u0) (err u106))
      (asserts! (not (is-eq seller-principal tx-sender)) (err u107))
      (asserts! (not (is-eq arbitrator-principal tx-sender)) (err u108))
      (asserts! (not (is-eq seller-principal arbitrator-principal)) (err u109))
      ;; (try! (contract-call? token-contract transfer escrow-amount tx-sender (as-contract tx-sender) none))
      (var-set seller seller-principal)
      (var-set arbitrator arbitrator-principal)
      (var-set amount escrow-amount)
      (var-set expiration-height (+ block-height ESCROW_DURATION))
      (var-set currency-type token-symbol)
      (var-set escrow-status "ACTIVE")
      (ok true)
    )
  )
)

(define-public (confirm-token-delivery)
  (let ((token-contract (unwrap! (map-get? supported-tokens (var-get currency-type)) (err u301))))
    (begin
      (asserts! (is-eq tx-sender (var-get seller)) (err u102))
      (asserts! (not (var-get is-disputed)) (err u103))
      (var-set is-complete true)
      ;; (try! (as-contract (contract-call? token-contract transfer (var-get amount) tx-sender (var-get seller) none)))
      (var-set escrow-status "COMPLETED")
      (ok true)
    )
  )
)


(define-map user-transaction-counts principal uint)
(define-map user-fee-tiers principal uint)

(define-constant TIER1-TRANSACTIONS u5)
(define-constant TIER2-TRANSACTIONS u20)
(define-constant TIER3-TRANSACTIONS u50)

(define-constant BASE-FEE-PERCENTAGE u3) ;; 3%
(define-constant TIER1-FEE-PERCENTAGE u25) ;; 2.5%
(define-constant TIER2-FEE-PERCENTAGE u2) ;; 2%
(define-constant TIER3-FEE-PERCENTAGE u15) ;; 1.5%

(define-public (update-user-transaction-count (user principal))
  (let ((current-count (default-to u0 (map-get? user-transaction-counts user))))
    (begin
      (map-set user-transaction-counts user (+ current-count u1))
      (let ((new-count (+ current-count u1)))
        (if (>= new-count TIER3-TRANSACTIONS) 
          (map-set user-fee-tiers user TIER3-FEE-PERCENTAGE)
          (if (>= new-count TIER2-TRANSACTIONS)
            (map-set user-fee-tiers user TIER2-FEE-PERCENTAGE)
            (if (>= new-count TIER1-TRANSACTIONS)
              (map-set user-fee-tiers user TIER1-FEE-PERCENTAGE)
              (map-set user-fee-tiers user BASE-FEE-PERCENTAGE)
            )
          )
        )
      )
      (ok true)
    )
  )
)
(define-public (get-user-fee-percentage (user principal))
  (ok (default-to BASE-FEE-PERCENTAGE (map-get? user-fee-tiers user)))
)

(define-public (calculate-fee-amount (tx-amount uint) (user principal))
  (let ((fee-percentage (default-to BASE-FEE-PERCENTAGE (map-get? user-fee-tiers user))))
    (ok (/ (* tx-amount fee-percentage) u100))
  )
)


(define-map collateralized-escrows uint {
  escrow-id: uint,
  collateral-amount: uint,
  collateral-provider: principal,
  is-released: bool
})

(define-data-var collateral-counter uint u0)

(define-public (add-collateral (escrow-id uint) (collateral-amount uint))
  (let ((collateral-id (var-get collateral-counter)))
    (begin
      ;; (asserts! (map-get? escrows escrow-id) (err u700))
      (asserts! (> collateral-amount u0) (err u701))
      (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
      (map-set collateralized-escrows collateral-id {
        escrow-id: escrow-id,
        collateral-amount: collateral-amount,
        collateral-provider: tx-sender,
        is-released: false
      })
      (var-set collateral-counter (+ collateral-id u1))
      (ok collateral-id)
    )
  )
)

(define-public (release-collateral (collateral-id uint))
  (let ((collateral (unwrap! (map-get? collateralized-escrows collateral-id) (err u702))))
    (begin
      (asserts! (not (get is-released collateral)) (err u703))
      (let ((escrow (unwrap! (map-get? escrows (get escrow-id collateral)) (err u704))))
        (asserts! (is-eq tx-sender (get arbitrator escrow)) (err u705))
        (try! (as-contract (stx-transfer? (get collateral-amount collateral) tx-sender (get collateral-provider collateral))))
        (map-set collateralized-escrows collateral-id (merge collateral { is-released: true }))
        (ok true)
      )
    )
  )
)



(define-map smart-conditions uint {
  condition-type: (string-ascii 20),
  target-value: uint,
  escrow-id: uint,
  is-met: bool
})

(define-data-var condition-counter uint u0)

(define-public (add-price-condition (escrow-id uint) (target-price uint))
  (let ((condition-id (var-get condition-counter)))
    (begin
      ;; (asserts! (map-get? escrows escrow-id) (err u600))
      (map-set smart-conditions condition-id {
        condition-type: "PRICE",
        target-value: target-price,
        escrow-id: escrow-id,
        is-met: false
      })
      (var-set condition-counter (+ condition-id u1))
      (ok condition-id)
    )
  )
)

(define-public (add-time-condition (escrow-id uint) (target-block-height uint))
  (let ((condition-id (var-get condition-counter)))
    (begin
      ;; (asserts! (map-get? escrows escrow-id) (err u600))
      (map-set smart-conditions condition-id {
        condition-type: "TIME",
        target-value: target-block-height,
        escrow-id: escrow-id,
        is-met: false
      })
      (var-set condition-counter (+ condition-id u1))
      (ok condition-id)
    )
  )
)

(define-public (check-time-condition (condition-id uint))
  (let ((condition (unwrap! (map-get? smart-conditions condition-id) (err u601))))
    (begin
      (asserts! (is-eq (get condition-type condition) "TIME") (err u602))
      (if (>= block-height (get target-value condition))
        (begin
          (map-set smart-conditions condition-id (merge condition { is-met: true }))
          (ok true)
        )
        (err u603)
      )
    )
  )
)


(define-map pool-participants uint (list 50 principal))
(define-map pool-contributions uint (list 50 uint))
(define-map pools uint {
    total-amount: uint,
    required-participants: uint,
    status: (string-ascii 20),
    pool-owner: principal
})
(define-data-var pool-counter uint u0)

(define-public (create-pool (required uint))
    (let ((pool-id (var-get pool-counter)))
        (begin
            (map-set pools pool-id {
                total-amount: u0,
                required-participants: required,
                status: "OPEN",
                pool-owner: tx-sender
            })
            (var-set pool-counter (+ pool-id u1))
            (ok pool-id))))

(define-public (join-pool (pool-id uint) (e-amount uint))
    (let ((pool (unwrap! (map-get? pools pool-id) (err u401))))
        (begin
            (try! (stx-transfer? e-amount tx-sender (as-contract tx-sender)))
            (map-set pools pool-id (merge pool {
                total-amount: (+ (get total-amount pool) e-amount)
            }))
            (map-set pool-participants pool-id (unwrap! (as-max-len? (append (default-to (list) (map-get? pool-participants pool-id)) tx-sender) u50) (err u404)))
            (map-set pool-contributions pool-id (unwrap! (as-max-len? (append (default-to (list) (map-get? pool-contributions pool-id)) e-amount) u50) (err u404)))
            (ok true))))



(define-map escrow-templates uint {
    name: (string-ascii 50),
    duration: uint,
    fee-percentage: uint,
    arbitrator: principal,
    requirements: (string-ascii 100)
})
(define-data-var template-counter uint u0)

(define-public (create-template 
    (name (string-ascii 50))
    (duration uint)
    (fee uint)
    (arbitrator-principal principal)
    (requirements (string-ascii 100)))
    (let ((template-id (var-get template-counter)))
        (begin
            (map-set escrow-templates template-id {
                name: name,
                duration: duration,
                fee-percentage: fee,
                arbitrator: arbitrator-principal,
                requirements: requirements
            })
            (var-set template-counter (+ template-id u1))
            (ok template-id))))

(define-public (use-template (template-id uint) (escrow-amount uint))
    (let ((template (unwrap! (map-get? escrow-templates template-id) (err u501))))
        (begin
            (try! (stx-transfer? escrow-amount tx-sender (as-contract tx-sender)))
            (var-set expiration-height (+ block-height (get duration template)))
            (var-set arbitrator (get arbitrator template))
            (var-set amount escrow-amount)
            (ok true))))