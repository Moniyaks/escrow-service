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
