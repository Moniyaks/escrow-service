;; Arbitrator Marketplace - Decentralized dispute resolution marketplace
;; Allows arbitrators to register, bid on cases, and build reputation

(define-map arbitrator-profiles principal {
    is-active: bool,
    hourly-rate: uint,
    stake-amount: uint,
    specializations: (list 5 (string-ascii 20)),
    languages: (list 3 (string-ascii 10)),
    min-case-value: uint,
    max-case-value: uint,
    total-cases: uint,
    successful-resolutions: uint,
    average-rating: uint,
    registration-height: uint,
    is-verified: bool
})

(define-map arbitrator-bids {case-id: uint, arbitrator: principal} {
    proposed-fee: uint,
    estimated-hours: uint,
    bid-height: uint,
    is-selected: bool,
    reasoning: (string-ascii 200)
})

(define-map dispute-cases uint {
    case-type: (string-ascii 20),
    transaction-value: uint,
    complexity-level: uint,
    preferred-language: (string-ascii 10),
    required-specialization: (string-ascii 20),
    deadline-height: uint,
    is-assigned: bool,
    assigned-arbitrator: (optional principal),
    client-principal: principal,
    case-status: (string-ascii 15)
})

(define-map arbitrator-ratings {arbitrator: principal, client: principal, case-id: uint} {
    communication-rating: uint,
    expertise-rating: uint,
    timeliness-rating: uint,
    fairness-rating: uint,
    overall-rating: uint,
    review-text: (string-ascii 300)
})

(define-map case-assignments uint {
    arbitrator: principal,
    assignment-height: uint,
    expected-completion: uint,
    actual-fee: uint,
    is-completed: bool,
    resolution-height: uint
})

(define-map arbitrator-earnings principal {
    total-earned: uint,
    pending-payment: uint,
    completed-cases: uint,
    current-active-cases: uint
})

(define-map arbitrator-availability principal {
    is-accepting-cases: bool,
    current-workload: uint,
    max-concurrent-cases: uint,
    next-available-date: uint,
    vacation-mode: bool
})

;; Data variables for marketplace management
(define-data-var case-counter uint u0)
(define-data-var minimum-arbitrator-stake uint u500000) ;; 0.5 STX
(define-data-var marketplace-fee-percentage uint u5) ;; 5% platform fee
(define-data-var verification-authority principal tx-sender)
(define-data-var max-bid-duration uint u1440) ;; ~10 days in blocks

;; Constants for rating validation
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant MIN-CASE-VALUE u10000) ;; 0.01 STX minimum
(define-constant MAX-CASE-VALUE u100000000) ;; 100 STX maximum

;; Register as an arbitrator in the marketplace
(define-public (register-arbitrator 
    (hourly-rate uint) 
    (specializations (list 5 (string-ascii 20)))
    (languages (list 3 (string-ascii 10)))
    (min-value uint)
    (max-value uint))
    (begin
        (asserts! (>= (stx-get-balance tx-sender) (var-get minimum-arbitrator-stake)) (err u100))
        (asserts! (> hourly-rate u0) (err u101))
        (asserts! (and (>= min-value MIN-CASE-VALUE) (<= max-value MAX-CASE-VALUE)) (err u102))
        (asserts! (< min-value max-value) (err u103))
        (try! (stx-transfer? (var-get minimum-arbitrator-stake) tx-sender (as-contract tx-sender)))
        (map-set arbitrator-profiles tx-sender {
            is-active: true,
            hourly-rate: hourly-rate,
            stake-amount: (var-get minimum-arbitrator-stake),
            specializations: specializations,
            languages: languages,
            min-case-value: min-value,
            max-case-value: max-value,
            total-cases: u0,
            successful-resolutions: u0,
            average-rating: u0,
            registration-height: stacks-block-height,
            is-verified: false
        })
        (map-set arbitrator-availability tx-sender {
            is-accepting-cases: true,
            current-workload: u0,
            max-concurrent-cases: u3,
            next-available-date: stacks-block-height,
            vacation-mode: false
        })
        (map-set arbitrator-earnings tx-sender {
            total-earned: u0,
            pending-payment: u0,
            completed-cases: u0,
            current-active-cases: u0
        })
        (ok true)))

;; Create a new dispute case for arbitrator bidding
(define-public (create-dispute-case 
    (case-type (string-ascii 20))
    (transaction-value uint)
    (complexity-level uint)
    (preferred-language (string-ascii 10))
    (required-specialization (string-ascii 20))
    (deadline-days uint))
    (let ((case-id (var-get case-counter)))
        (begin
            (asserts! (> transaction-value u0) (err u200))
            (asserts! (and (>= complexity-level u1) (<= complexity-level u5)) (err u201))
            (asserts! (> deadline-days u0) (err u202))
            (map-set dispute-cases case-id {
                case-type: case-type,
                transaction-value: transaction-value,
                complexity-level: complexity-level,
                preferred-language: preferred-language,
                required-specialization: required-specialization,
                deadline-height: (+ stacks-block-height (* deadline-days u144)),
                is-assigned: false,
                assigned-arbitrator: none,
                client-principal: tx-sender,
                case-status: "OPEN_FOR_BIDS"
            })
            (var-set case-counter (+ case-id u1))
            (ok case-id))))

;; Arbitrator submits a bid for a dispute case
(define-public (submit-bid 
    (case-id uint)
    (proposed-fee uint)
    (estimated-hours uint)
    (reasoning (string-ascii 200)))
    (let ((case-data (unwrap! (map-get? dispute-cases case-id) (err u300)))
          (arbitrator-data (unwrap! (map-get? arbitrator-profiles tx-sender) (err u301)))
          (availability (unwrap! (map-get? arbitrator-availability tx-sender) (err u302))))
        (begin
            (asserts! (get is-active arbitrator-data) (err u303))
            (asserts! (get is-accepting-cases availability) (err u304))
            (asserts! (not (get is-assigned case-data)) (err u305))
            (asserts! (is-eq (get case-status case-data) "OPEN_FOR_BIDS") (err u306))
            (asserts! (and (>= (get transaction-value case-data) (get min-case-value arbitrator-data))
                          (<= (get transaction-value case-data) (get max-case-value arbitrator-data))) (err u307))
            (asserts! (> proposed-fee u0) (err u308))
            (asserts! (> estimated-hours u0) (err u309))
            (map-set arbitrator-bids {case-id: case-id, arbitrator: tx-sender} {
                proposed-fee: proposed-fee,
                estimated-hours: estimated-hours,
                bid-height: stacks-block-height,
                is-selected: false,
                reasoning: reasoning
            })
            (ok true))))

;; Client selects an arbitrator from submitted bids
(define-public (select-arbitrator (case-id uint) (chosen-arbitrator principal))
    (let ((case-data (unwrap! (map-get? dispute-cases case-id) (err u400)))
          (bid-data (unwrap! (map-get? arbitrator-bids {case-id: case-id, arbitrator: chosen-arbitrator}) (err u401)))
          (arbitrator-data (unwrap! (map-get? arbitrator-profiles chosen-arbitrator) (err u402))))
        (begin
            (asserts! (is-eq tx-sender (get client-principal case-data)) (err u403))
            (asserts! (not (get is-assigned case-data)) (err u404))
            (asserts! (get is-active arbitrator-data) (err u405))
            (try! (stx-transfer? (get proposed-fee bid-data) tx-sender (as-contract tx-sender)))
            (map-set dispute-cases case-id (merge case-data {
                is-assigned: true,
                assigned-arbitrator: (some chosen-arbitrator),
                case-status: "IN_PROGRESS"
            }))
            (map-set arbitrator-bids {case-id: case-id, arbitrator: chosen-arbitrator} 
                    (merge bid-data {is-selected: true}))
            (map-set case-assignments case-id {
                arbitrator: chosen-arbitrator,
                assignment-height: stacks-block-height,
                expected-completion: (+ stacks-block-height (* (get estimated-hours bid-data) u6)),
                actual-fee: (get proposed-fee bid-data),
                is-completed: false,
                resolution-height: u0
            })
            (let ((earnings (unwrap! (map-get? arbitrator-earnings chosen-arbitrator) (err u406))))
                (map-set arbitrator-earnings chosen-arbitrator (merge earnings {
                    pending-payment: (+ (get pending-payment earnings) (get proposed-fee bid-data)),
                    current-active-cases: (+ (get current-active-cases earnings) u1)
                })))
            (ok true))))

;; Mark case as resolved and release payment to arbitrator
(define-public (complete-case-resolution (case-id uint))
    (let ((case-data (unwrap! (map-get? dispute-cases case-id) (err u500)))
          (assignment (unwrap! (map-get? case-assignments case-id) (err u501)))
          (arbitrator (get arbitrator assignment)))
        (begin
            (asserts! (is-eq tx-sender arbitrator) (err u502))
            (asserts! (is-eq (get case-status case-data) "IN_PROGRESS") (err u503))
            (asserts! (not (get is-completed assignment)) (err u504))
            (let ((platform-fee (/ (* (get actual-fee assignment) (var-get marketplace-fee-percentage)) u100))
                  (arbitrator-payment (- (get actual-fee assignment) platform-fee)))
                (try! (as-contract (stx-transfer? arbitrator-payment tx-sender arbitrator)))
                (map-set dispute-cases case-id (merge case-data {case-status: "RESOLVED"}))
                (map-set case-assignments case-id (merge assignment {
                    is-completed: true,
                    resolution-height: stacks-block-height
                }))
                (let ((arbitrator-profile (unwrap! (map-get? arbitrator-profiles arbitrator) (err u505)))
                      (earnings (unwrap! (map-get? arbitrator-earnings arbitrator) (err u506))))
                    (map-set arbitrator-profiles arbitrator (merge arbitrator-profile {
                        total-cases: (+ (get total-cases arbitrator-profile) u1),
                        successful-resolutions: (+ (get successful-resolutions arbitrator-profile) u1)
                    }))
                    (map-set arbitrator-earnings arbitrator (merge earnings {
                        total-earned: (+ (get total-earned earnings) arbitrator-payment),
                        pending-payment: (- (get pending-payment earnings) (get actual-fee assignment)),
                        completed-cases: (+ (get completed-cases earnings) u1),
                        current-active-cases: (- (get current-active-cases earnings) u1)
                    }))))
            (ok true))))

;; Client rates arbitrator after case completion
(define-public (rate-arbitrator 
    (case-id uint)
    (arbitrator principal)
    (communication uint)
    (expertise uint)
    (timeliness uint)
    (fairness uint)
    (review-text (string-ascii 300)))
    (let ((case-data (unwrap! (map-get? dispute-cases case-id) (err u600)))
          (assignment (unwrap! (map-get? case-assignments case-id) (err u601))))
        (begin
            (asserts! (is-eq tx-sender (get client-principal case-data)) (err u602))
            (asserts! (is-eq arbitrator (get arbitrator assignment)) (err u603))
            (asserts! (get is-completed assignment) (err u604))
            (asserts! (and (>= communication MIN-RATING) (<= communication MAX-RATING)) (err u605))
            (asserts! (and (>= expertise MIN-RATING) (<= expertise MAX-RATING)) (err u606))
            (asserts! (and (>= timeliness MIN-RATING) (<= timeliness MAX-RATING)) (err u607))
            (asserts! (and (>= fairness MIN-RATING) (<= fairness MAX-RATING)) (err u608))
            (let ((overall-rating (/ (+ communication expertise timeliness fairness) u4)))
                (map-set arbitrator-ratings {arbitrator: arbitrator, client: tx-sender, case-id: case-id} {
                    communication-rating: communication,
                    expertise-rating: expertise,
                    timeliness-rating: timeliness,
                    fairness-rating: fairness,
                    overall-rating: overall-rating,
                    review-text: review-text
                })
                (try! (update-arbitrator-average-rating arbitrator))
                (ok true)))))

;; Update arbitrator's average rating based on all reviews
(define-private (update-arbitrator-average-rating (arbitrator principal))
    (let ((profile (unwrap! (map-get? arbitrator-profiles arbitrator) (err u700))))
        (if (> (get total-cases profile) u0)
            (let ((total-rating-sum (fold calculate-rating-sum 
                                        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) 
                                        {arbitrator: arbitrator, sum: u0, count: u0}))
                  (average (if (> (get count total-rating-sum) u0) 
                             (/ (get sum total-rating-sum) (get count total-rating-sum)) 
                             u0)))
                (begin
                    (map-set arbitrator-profiles arbitrator (merge profile {average-rating: average}))
                    (ok true)))
            (ok true))))

;; Helper function for rating calculation
(define-private (calculate-rating-sum 
    (case-id uint) 
    (acc {arbitrator: principal, sum: uint, count: uint}))
    (match (map-get? arbitrator-ratings {arbitrator: (get arbitrator acc), client: tx-sender, case-id: case-id})
        rating (merge acc {
            sum: (+ (get sum acc) (get overall-rating rating)),
            count: (+ (get count acc) u1)
        })
        acc))

;; Verify arbitrator status (admin function)
(define-public (verify-arbitrator (arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get verification-authority)) (err u800))
        (match (map-get? arbitrator-profiles arbitrator)
            profile (begin
                (map-set arbitrator-profiles arbitrator (merge profile {is-verified: true}))
                (ok true))
            (err u801))))

;; Update arbitrator availability status
(define-public (update-availability 
    (accepting-cases bool)
    (max-concurrent uint)
    (vacation-mode bool))
    (match (map-get? arbitrator-availability tx-sender)
        availability (begin
            (map-set arbitrator-availability tx-sender (merge availability {
                is-accepting-cases: accepting-cases,
                max-concurrent-cases: max-concurrent,
                vacation-mode: vacation-mode
            }))
            (ok true))
        (err u900)))

;; Get arbitrator profile information
(define-read-only (get-arbitrator-profile (arbitrator principal))
    (map-get? arbitrator-profiles arbitrator))

;; Get case details
(define-read-only (get-case-details (case-id uint))
    (map-get? dispute-cases case-id))

;; Get bid information
(define-read-only (get-bid-details (case-id uint) (arbitrator principal))
    (map-get? arbitrator-bids {case-id: case-id, arbitrator: arbitrator}))

;; Get arbitrator earnings summary
(define-read-only (get-earnings-summary (arbitrator principal))
    (map-get? arbitrator-earnings arbitrator))


