(define-data-var buyer principal tx-sender)
(define-data-var seller principal tx-sender)
(define-data-var arbitrator principal tx-sender)
(define-data-var amount uint u0)
(define-data-var is-complete bool false)
(define-data-var is-disputed bool false)

;; Buyer initiates the escrow by locking funds
(define-public (initiate-escrow (seller-principal principal) (arbitrator-principal principal) (escrow-amount uint))
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
