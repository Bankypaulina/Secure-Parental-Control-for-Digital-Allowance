;; Secure Parental Control for Digital Allowance

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))

;; Data Maps
(define-map parents principal bool)
(define-map allowances { child: principal } { amount: uint, parent: principal })
(define-map spending-history 
    { child: principal } 
    { total-spent: uint, last-spent: uint })

;; Public Functions
(define-public (register-as-parent)
    (begin
        (map-set parents tx-sender true)
        (ok true)))

(define-public (set-allowance (child principal) (amount uint))
    (if (is-parent tx-sender)
        (begin
            (map-set allowances 
                { child: child }
                { amount: amount, parent: tx-sender })
            (ok true))
        ERR-NOT-AUTHORIZED))

(define-public (spend (amount uint))
    (let ((allowance (get-allowance tx-sender)))
        (if (>= (get amount allowance) amount)
            (begin
                (map-set allowances 
                    { child: tx-sender }
                    { amount: (- (get amount allowance) amount),
                      parent: (get parent allowance) })
                (ok true))
            ERR-INSUFFICIENT-BALANCE)))

;; Read Only Functions
(define-read-only (is-parent (address principal))
    (default-to false (map-get? parents address)))

(define-read-only (get-allowance (child principal))
    (default-to { amount: u0, parent: tx-sender }
        (map-get? allowances { child: child })))
