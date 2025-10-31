;; adjudication.clar
;; Purpose: Damage assessment inputs, fraud signal capture, adjuster assignment,
;;          and settlement approval tracking. No cross-contract calls or traits.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; constants and error codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-constant ERR-UNAUTHORIZED u200)
(define-constant ERR-ADJUSTER-EXISTS u201)
(define-constant ERR-ADJUSTER-NOT-FOUND u202)
(define-constant ERR-ASSIGN-EXISTS u203)
(define-constant ERR-ASSIGN-NOT-FOUND u204)

(define-constant STATUS-PROPOSED "proposed")
(define-constant STATUS-APPROVED "approved")

;;;;;;;;;;;;;;;;;;;
;; admin and data ;;
;;;;;;;;;;;;;;;;;;;
(define-data-var admin (optional principal) none)

(define-map adjusters
  { who: principal }
  { active: bool })

(define-map assignments
  { claim-id: uint }
  { adjuster: principal })

(define-map damages
  { claim-id: uint }
  { est-repair-cost: uint,
    total-loss: bool,
    mileage: uint,
    pre-existing-damage: bool,
    ai-score: uint })

(define-map fraud
  { claim-id: uint }
  { late-reporting: bool,
    prior-claims: uint,
    suspicious-pattern: bool,
    ip-distance: uint,
    fraud-score: uint })

(define-map settlements
  { claim-id: uint }
  { amount: uint,
    status: (string-ascii 20) })

;;;;;;;;;;;;;;;;;;;;;;;;
;; utility calculations ;;
;;;;;;;;;;;;;;;;;;;;;;;;
(define-private (cap-100 (n uint)) (if (> n u100) u100 n))

(define-private (calc-damage-score (est-repair-cost uint)
                                   (total-loss bool)
                                   (mileage uint)
                                   (pre-existing-damage bool))
  (let (
        (cost-part (/ est-repair-cost u1000))
        (tl-part (if total-loss u50 u0))
        (mile-part (if (> mileage u150000) u10 u0))
        (pre-part (if pre-existing-damage u10 u0))
       )
    (cap-100 (+ cost-part (+ tl-part (+ mile-part pre-part))))))

(define-private (calc-fraud-score (late-reporting bool)
                                  (prior-claims uint)
                                  (suspicious-pattern bool)
                                  (ip-distance uint))
  (let (
        (late (if late-reporting u20 u0))
        (prior (let ((raw (* prior-claims u10))) (if (> raw u60) u60 raw)))
        (sus (if suspicious-pattern u30 u0))
        (ip (let ((part (/ ip-distance u100))) (if (> part u20) u20 part)))
       )
    (cap-100 (+ late (+ prior (+ sus ip))))))

;;;;;;;;;;;;;;;;;;;;;;
;; admin operations  ;;
;;;;;;;;;;;;;;;;;;;;;;
(define-public (initialize-admin)
  (match (var-get admin)
    a (err ERR-UNAUTHORIZED)
    (begin (var-set admin (some tx-sender)) (ok true))))

(define-public (register-adjuster (who principal))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? adjusters { who: who })
                ex (err ERR-ADJUSTER-EXISTS)
                (begin (map-set adjusters { who: who } { active: true }) (ok true)))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

(define-public (deactivate-adjuster (who principal))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? adjusters { who: who })
                adj (begin (map-set adjusters { who: who } { active: false }) (ok true))
                (err ERR-ADJUSTER-NOT-FOUND))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; adjuster assignment   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (assign-adjuster (claim-id uint) (who principal))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? adjusters { who: who })
                adj
                  (if (get active adj)
                      (match (map-get? assignments { claim-id: claim-id })
                        existing (err ERR-ASSIGN-EXISTS)
                        (begin (map-set assignments { claim-id: claim-id } { adjuster: who }) (ok true)))
                      (err ERR-ADJUSTER-NOT-FOUND))
                (err ERR-ADJUSTER-NOT-FOUND))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; assessment and fraud recording  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (record-damage-info (claim-id uint)
                                  (est-repair-cost uint)
                                  (total-loss bool)
                                  (mileage uint)
                                  (pre-existing-damage bool))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (let ((score (calc-damage-score est-repair-cost total-loss mileage pre-existing-damage)))
                (map-set damages { claim-id: claim-id }
                                 { est-repair-cost: est-repair-cost,
                                   total-loss: total-loss,
                                   mileage: mileage,
                                   pre-existing-damage: pre-existing-damage,
                                   ai-score: score })
                (ok score))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

(define-public (record-fraud-signal (claim-id uint)
                                   (late-reporting bool)
                                   (prior-claims uint)
                                   (suspicious-pattern bool)
                                   (ip-distance uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (let ((score (calc-fraud-score late-reporting prior-claims suspicious-pattern ip-distance)))
                (map-set fraud { claim-id: claim-id }
                              { late-reporting: late-reporting,
                                prior-claims: prior-claims,
                                suspicious-pattern: suspicious-pattern,
                                ip-distance: ip-distance,
                                fraud-score: score })
                (ok score))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;;;
;; settlement tracking ;;
;;;;;;;;;;;;;;;;;;;;;;
(define-private (is-authorized-adjuster (claim-id uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              true
              (match (map-get? assignments { claim-id: claim-id })
                asg (is-eq tx-sender (get adjuster asg))
                false)))
        false)))

(define-public (propose-settlement (claim-id uint) (amount uint))
  (if (is-authorized-adjuster claim-id)
      (begin (map-set settlements { claim-id: claim-id } { amount: amount, status: STATUS-PROPOSED }) (ok true))
      (err ERR-UNAUTHORIZED)))

(define-public (approve-settlement (claim-id uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? settlements { claim-id: claim-id })
                s (begin (map-set settlements { claim-id: claim-id } { amount: (get amount s), status: STATUS-APPROVED }) (ok true))
                (begin (map-set settlements { claim-id: claim-id } { amount: u0, status: STATUS-APPROVED }) (ok true)))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;
;; read-only views  ;;
;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-adjuster (who principal))
  (ok (map-get? adjusters { who: who })))

(define-read-only (get-assignment (claim-id uint))
  (ok (map-get? assignments { claim-id: claim-id })))

(define-read-only (get-damage (claim-id uint))
  (ok (map-get? damages { claim-id: claim-id })))

(define-read-only (get-fraud (claim-id uint))
  (ok (map-get? fraud { claim-id: claim-id })))

(define-read-only (get-settlement (claim-id uint))
  (ok (map-get? settlements { claim-id: claim-id })))
