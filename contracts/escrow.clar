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
