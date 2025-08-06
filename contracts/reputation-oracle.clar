(define-map reputation-oracles principal {
    stake-amount: uint,
    accuracy-score: uint,
    total-submissions: uint,
    is-active: bool,
    registration-height: uint
})

(define-map reputation-submissions {oracle: principal, user: principal, submission-id: uint} {
    reputation-score: uint,
    confidence-level: uint,
    submission-height: uint,
    evidence-hash: (buff 32)
})

(define-map user-reputation-consensus principal {
    final-score: uint,
    total-weight: uint,
    last-updated: uint,
    submission-count: uint
})

(define-map oracle-disputes uint {
    oracle: principal,
    disputer: principal,
    disputed-user: principal,
    stake-amount: uint,
    is-resolved: bool,
    resolution-height: uint
})

(define-data-var oracle-stake-requirement uint u1000000)
(define-data-var min-oracles-for-consensus uint u3)
(define-data-var reputation-decay-rate uint u1)
(define-data-var dispute-counter uint u0)
(define-data-var submission-counter uint u0)

(define-constant MIN_CONFIDENCE u1)
(define-constant MAX_CONFIDENCE u100)
(define-constant MIN_REPUTATION u0)
(define-constant MAX_REPUTATION u1000)
(define-constant DISPUTE_WINDOW u1440)

(define-public (register-oracle)
    (begin
        (asserts! (>= (stx-get-balance tx-sender) (var-get oracle-stake-requirement)) (err u1001))
        (try! (stx-transfer? (var-get oracle-stake-requirement) tx-sender (as-contract tx-sender)))
        (map-set reputation-oracles tx-sender {
            stake-amount: (var-get oracle-stake-requirement),
            accuracy-score: u100,
            total-submissions: u0,
            is-active: true,
            registration-height: stacks-block-height
        })
        (ok true)))

(define-public (submit-reputation 
    (target-user principal) 
    (reputation-score uint) 
    (confidence-level uint)
    (evidence-hash (buff 32)))
    (let ((oracle-data (unwrap! (map-get? reputation-oracles tx-sender) (err u1002)))
          (submission-id (var-get submission-counter)))
        (begin
            (asserts! (get is-active oracle-data) (err u1003))
            (asserts! (and (>= reputation-score MIN_REPUTATION) (<= reputation-score MAX_REPUTATION)) (err u1004))
            (asserts! (and (>= confidence-level MIN_CONFIDENCE) (<= confidence-level MAX_CONFIDENCE)) (err u1005))
            (map-set reputation-submissions {oracle: tx-sender, user: target-user, submission-id: submission-id} {
                reputation-score: reputation-score,
                confidence-level: confidence-level,
                submission-height: stacks-block-height,
                evidence-hash: evidence-hash
            })
            (map-set reputation-oracles tx-sender (merge oracle-data {
                total-submissions: (+ (get total-submissions oracle-data) u1)
            }))
            (var-set submission-counter (+ submission-id u1))
            (unwrap! (calculate-reputation-consensus target-user) (err u1006))
            (ok submission-id))))

(define-private (calculate-reputation-consensus (target-user principal))
    (let ((current-consensus (default-to {final-score: u500, total-weight: u0, last-updated: u0, submission-count: u0} 
                                       (map-get? user-reputation-consensus target-user))))
        (begin
            (map-set user-reputation-consensus target-user (merge current-consensus {
                last-updated: stacks-block-height,
                submission-count: (+ (get submission-count current-consensus) u1)
            }))
            (ok true))))

(define-public (dispute-oracle-submission 
    (oracle principal) 
    (disputed-user principal) 
    (submission-id uint))
    (let ((dispute-id (var-get dispute-counter))
          (oracle-data (unwrap! (map-get? reputation-oracles oracle) (err u1006))))
        (begin
            (asserts! (>= (stx-get-balance tx-sender) (get stake-amount oracle-data)) (err u1007))
            (try! (stx-transfer? (get stake-amount oracle-data) tx-sender (as-contract tx-sender)))
            (map-set oracle-disputes dispute-id {
                oracle: oracle,
                disputer: tx-sender,
                disputed-user: disputed-user,
                stake-amount: (get stake-amount oracle-data),
                is-resolved: false,
                resolution-height: u0
            })
            (var-set dispute-counter (+ dispute-id u1))
            (ok dispute-id))))

(define-public (resolve-dispute (dispute-id uint) (oracle-wins bool))
    (let ((dispute (unwrap! (map-get? oracle-disputes dispute-id) (err u1008))))
        (begin
            (asserts! (not (get is-resolved dispute)) (err u1009))
            (if oracle-wins
                (begin
                    (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender (get oracle dispute))))
                    (let ((oracle-data (unwrap! (map-get? reputation-oracles (get oracle dispute)) (err u1010))))
                        (map-set reputation-oracles (get oracle dispute) (merge oracle-data {
                            accuracy-score: (+ (get accuracy-score oracle-data) u10)
                        }))))
                (begin
                    (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender (get disputer dispute))))
                    (let ((oracle-data (unwrap! (map-get? reputation-oracles (get oracle dispute)) (err u1010))))
                        (map-set reputation-oracles (get oracle dispute) (merge oracle-data {
                            accuracy-score: (if (> (get accuracy-score oracle-data) u10) 
                                           (- (get accuracy-score oracle-data) u10) 
                                           u0)
                        })))))
            (map-set oracle-disputes dispute-id (merge dispute {
                is-resolved: true,
                resolution-height: stacks-block-height
            }))
            (ok true))))

(define-public (get-weighted-reputation (user principal))
    (let ((consensus (default-to {final-score: u500, total-weight: u0, last-updated: u0, submission-count: u0} 
                                (map-get? user-reputation-consensus user))))
        (if (>= (get submission-count consensus) (var-get min-oracles-for-consensus))
            (ok (get final-score consensus))
            (ok u500))))

(define-public (update-oracle-stake-requirement (new-requirement uint))
    (begin
        (var-set oracle-stake-requirement new-requirement)
        (ok true)))

(define-public (deactivate-oracle (oracle principal))
    (let ((oracle-data (unwrap! (map-get? reputation-oracles oracle) (err u1011))))
        (begin
            (asserts! (< (get accuracy-score oracle-data) u50) (err u1012))
            (map-set reputation-oracles oracle (merge oracle-data {is-active: false}))
            (try! (as-contract (stx-transfer? (get stake-amount oracle-data) tx-sender oracle)))
            (ok true))))

(define-public (calculate-reputation-based-fee (user principal) (base-fee uint))
    (let ((reputation (unwrap! (get-weighted-reputation user) (err u1013))))
        (if (> reputation u800)
            (ok (/ (* base-fee u50) u100))
            (if (> reputation u600)
                (ok (/ (* base-fee u75) u100))
                (if (> reputation u400)
                    (ok base-fee)
                    (ok (/ (* base-fee u150) u100)))))))

(define-public (get-oracle-info (oracle principal))
    (ok (map-get? reputation-oracles oracle)))

(define-public (get-user-reputation-info (user principal))
    (ok (map-get? user-reputation-consensus user)))

(define-public (withdraw-oracle-stake)
    (let ((oracle-data (unwrap! (map-get? reputation-oracles tx-sender) (err u1014))))
        (begin
            (asserts! (not (get is-active oracle-data)) (err u1015))
            (asserts! (> (- stacks-block-height (get registration-height oracle-data)) u10080) (err u1016))
            (try! (as-contract (stx-transfer? (get stake-amount oracle-data) tx-sender tx-sender)))
            (map-delete reputation-oracles tx-sender)
            (ok true))))

;; (define-public (batch-submit-reputations 
;;     (users (list 10 principal)) 
;;     (scores (list 10 uint)) 
;;     (confidences (list 10 uint))
;;     (evidence-hashes (list 10 (buff 32))))
;;     (let ((oracle-data (unwrap! (map-get? reputation-oracles tx-sender) (err u1017))))
;;         (begin
;;             (asserts! (get is-active oracle-data) (err u1018))
;;             (asserts! (is-eq (len users) (len scores)) (err u1019))
;;             (asserts! (is-eq (len scores) (len confidences)) (err u1020))
;;             (asserts! (is-eq (len confidences) (len evidence-hashes)) (err u1021))
;;             (fold process-batch-submission 
;;                   (zip users (zip users (zip users evidence-hashes)))
;;                   (ok (list)))
;;             (ok true))))

(define-private (process-batch-submission 
    (data {user: principal, score-conf-hash: {score: uint, conf-hash: {confidence: uint, evidence: (buff 32)}}})
    (acc (response (list 10 uint) uint)))
    (match acc
        success (match (submit-reputation 
                       (get user data)
                       (get score (get score-conf-hash data))
                       (get confidence (get conf-hash (get score-conf-hash data)))
                       (get evidence (get conf-hash (get score-conf-hash data))))
                   ok-val (ok (unwrap! (as-max-len? (append success ok-val) u10) (err u1022)))
                   err-val (err err-val))
        error (err error)))

(define-private (zip (list-a (list 10 principal)) (list-b (list 10 {score: uint, conf-hash: {confidence: uint, evidence: (buff 32)}})))
    (map combine-elements list-a list-b))

(define-private (combine-elements (a principal) (b {score: uint, conf-hash: {confidence: uint, evidence: (buff 32)}}))
    {user: a, score-conf-hash: b})