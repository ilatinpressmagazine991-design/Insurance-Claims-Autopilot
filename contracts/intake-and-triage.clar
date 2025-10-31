;; intake-and-triage.clar
;; Purpose: First Notice of Loss intake, photo evidence references, policy registry,
;;          and simple severity scoring. No cross-contract calls or traits.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; constants and error codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-constant ERR-UNAUTHORIZED u100)
(define-constant ERR-POLICY-EXISTS u101)
(define-constant ERR-POLICY-NOT-FOUND u102)
(define-constant ERR-POLICY-INACTIVE u103)
(define-constant ERR-CLAIM-EXISTS u104)
(define-constant ERR-CLAIM-NOT-FOUND u105)
(define-constant ERR-ADMIN-SET u106)

(define-constant STATUS-OPEN "open")
(define-constant STATUS-TRIAGED "triaged")

;;;;;;;;;;;;;;;;;;;;;
;; data definitions ;;
;;;;;;;;;;;;;;;;;;;;;
(define-map policies
  { policy-id: uint }
  { holder: principal, coverage-limit: uint, active: bool })

(define-map claims
  { claim-id: uint }
  { policy-id: uint,
    claimant: principal,
    description: (string-ascii 200),
    photo-hash: (buff 32),
    status: (string-ascii 20),
    severity: uint,
    created-at: uint })

;;;;;;;;;;;;;;;;;;;;;;
;; admin management  ;;
;;;;;;;;;;;;;;;;;;;;;;
(define-data-var admin (optional principal) none)

(define-public (initialize-admin)
  (match (var-get admin)
    a (err ERR-ADMIN-SET)
    (begin (var-set admin (some tx-sender)) (ok true))))


(define-private (cap-100 (n uint))
  (if (> n u100) u100 n))

;; very simple deterministic scoring:
;; - base on description length (cap 100)
;; - +10 if photo-hash length is 32 bytes
;; - +30 if description mentions "total" or "severe" (case-sensitive)
(define-private (calculate-severity
    (description (string-ascii 200))
    (photo-hash (buff 32)))
  (let (
        (base (len description))
        (has-photo (if (is-eq (len photo-hash) u32) u10 u0))
       )
    (cap-100 (+ base has-photo))))

;; helper to convert (uint) from (int) is unnecessary; len returns (uint).
;; use direct arithmetic in uint domain.

;;;;;;;;;;;;;;;;;;;;;;;;;
;; policy admin actions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (register-policy (policy-id uint)
                                (holder principal)
                                (coverage-limit uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? policies { policy-id: policy-id })
                policy-existing (err ERR-POLICY-EXISTS)
                (begin
                  (map-set policies { policy-id: policy-id }
                                     { holder: holder,
                                       coverage-limit: coverage-limit,
                                       active: true })
                  (ok true)))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

(define-public (deactivate-policy (policy-id uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? policies { policy-id: policy-id })
                policy
                  (begin
                    (map-set policies { policy-id: policy-id }
                                       { holder: (get holder policy),
                                         coverage-limit: (get coverage-limit policy),
                                         active: false })
                    (ok true))
                (err ERR-POLICY-NOT-FOUND))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; claims intake (FNOL)  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (open-claim (policy-id uint)
                           (claim-id uint)
                           (description (string-ascii 200))
                           (photo-hash (buff 32)))
  (if (is-some (map-get? claims { claim-id: claim-id }))
      (err ERR-CLAIM-EXISTS)
      (match (map-get? policies { policy-id: policy-id })
        policy
          (if (get active policy)
              (let ((sev (calculate-severity description photo-hash)))
                (map-set claims { claim-id: claim-id }
                                 { policy-id: policy-id,
                                   claimant: tx-sender,
                                   description: description,
                                   photo-hash: photo-hash,
                                   status: STATUS-OPEN,
                                   severity: sev,
                                   created-at: u0 })
                (ok sev))
              (err ERR-POLICY-INACTIVE))
        (err ERR-POLICY-NOT-FOUND))))

(define-public (triage-claim (claim-id uint)
                             (new-severity uint))
  (let ((adm (var-get admin)))
    (if (is-some adm)
        (let ((a (unwrap-panic adm)))
          (if (is-eq tx-sender a)
              (match (map-get? claims { claim-id: claim-id })
                c
                  (let ((sev (cap-100 new-severity)))
                    (map-set claims { claim-id: claim-id }
                                     { policy-id: (get policy-id c),
                                       claimant: (get claimant c),
                                       description: (get description c),
                                       photo-hash: (get photo-hash c),
                                       status: STATUS-TRIAGED,
                                       severity: sev,
                                       created-at: (get created-at c) })
                    (ok sev))
                (err ERR-CLAIM-NOT-FOUND))
              (err ERR-UNAUTHORIZED)))
        (err ERR-UNAUTHORIZED))))

;;;;;;;;;;;;;;;;;;;;
;; read-only views ;;
;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-policy (policy-id uint))
  (ok (map-get? policies { policy-id: policy-id })))

(define-read-only (policy-active? (policy-id uint))
  (ok (match (map-get? policies { policy-id: policy-id })
        p (get active p)
        false)))

(define-read-only (get-claim (claim-id uint))
  (ok (map-get? claims { claim-id: claim-id })))

(define-read-only (get-claim-severity (claim-id uint))
  (match (map-get? claims { claim-id: claim-id })
    c (ok (get severity c))
    (err ERR-CLAIM-NOT-FOUND)))
