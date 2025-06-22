
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-VAULT-BALANCE (err u102))
(define-constant ERR-VAULT-NOT-FOUND (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))

(define-map vault-balances
    { parent: principal }
    {
        stx-balance: uint,
        last-interest-calc: uint,
        total-interest-earned: uint,
        auto-allowance-enabled: bool
    }
)

(define-map vault-allowance-settings
    { parent: principal, child: principal }
    {
        weekly-amount: uint,
        last-distribution: uint,
        total-distributed: uint,
        active: bool
    }
)

(define-map vault-transactions
    { parent: principal, tx-id: uint }
    {
        transaction-type: (string-ascii 20),
        amount: uint,
        timestamp: uint,
        child: (optional principal)
    }
)

(define-data-var next-tx-id uint u1)
(define-data-var interest-rate uint u5)

(define-public (deposit-to-vault (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (let ((current-vault (default-to
                {
                    stx-balance: u0,
                    last-interest-calc: stacks-block-height,
                    total-interest-earned: u0,
                    auto-allowance-enabled: false
                }
                (map-get? vault-balances { parent: tx-sender }))))
            
            (map-set vault-balances
                { parent: tx-sender }
                {
                    stx-balance: (+ (get stx-balance current-vault) amount),
                    last-interest-calc: stacks-block-height,
                    total-interest-earned: (get total-interest-earned current-vault),
                    auto-allowance-enabled: (get auto-allowance-enabled current-vault)
                }
            )
            
            (map-set vault-transactions
                { parent: tx-sender, tx-id: (var-get next-tx-id) }
                {
                    transaction-type: "deposit",
                    amount: amount,
                    timestamp: stacks-block-height,
                    child: none
                }
            )
            
            (var-set next-tx-id (+ (var-get next-tx-id) u1))
            (ok amount)
        )
    )
)

(define-public (withdraw-from-vault (amount uint))
    (let ((vault (unwrap! (map-get? vault-balances { parent: tx-sender }) ERR-VAULT-NOT-FOUND)))
        (asserts! (>= (get stx-balance vault) amount) ERR-INSUFFICIENT-VAULT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (try! (calculate-and-add-interest tx-sender))
        
        (let ((updated-vault (unwrap! (map-get? vault-balances { parent: tx-sender }) ERR-VAULT-NOT-FOUND)))
            (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
            
            (map-set vault-balances
                { parent: tx-sender }
                {
                    stx-balance: (- (get stx-balance updated-vault) amount),
                    last-interest-calc: stacks-block-height,
                    total-interest-earned: (get total-interest-earned updated-vault),
                    auto-allowance-enabled: (get auto-allowance-enabled updated-vault)
                }
            )
            
            (map-set vault-transactions
                { parent: tx-sender, tx-id: (var-get next-tx-id) }
                {
                    transaction-type: "withdrawal",
                    amount: amount,
                    timestamp: stacks-block-height,
                    child: none
                }
            )
            
            (var-set next-tx-id (+ (var-get next-tx-id) u1))
            (ok amount)
        )
    )
)

(define-public (setup-auto-allowance (child principal) (weekly-amount uint))
    (let ((vault (unwrap! (map-get? vault-balances { parent: tx-sender }) ERR-VAULT-NOT-FOUND)))
        (asserts! (> weekly-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set vault-allowance-settings
            { parent: tx-sender, child: child }
            {
                weekly-amount: weekly-amount,
                last-distribution: stacks-block-height,
                total-distributed: u0,
                active: true
            }
        )
        
        (map-set vault-balances
            { parent: tx-sender }
            {
                stx-balance: (get stx-balance vault),
                last-interest-calc: (get last-interest-calc vault),
                total-interest-earned: (get total-interest-earned vault),
                auto-allowance-enabled: true
            }
        )
        
        (ok true)
    )
)

(define-public (distribute-weekly-allowance (child principal))
    (let (
        (vault (unwrap! (map-get? vault-balances { parent: tx-sender }) ERR-VAULT-NOT-FOUND))
        (allowance-setting (unwrap! (map-get? vault-allowance-settings { parent: tx-sender, child: child }) ERR-VAULT-NOT-FOUND))
    )
        (asserts! (get active allowance-setting) ERR-NOT-AUTHORIZED)
        (asserts! (>= stacks-block-height (+ (get last-distribution allowance-setting) u1008)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (get stx-balance vault) (get weekly-amount allowance-setting)) ERR-INSUFFICIENT-VAULT-BALANCE)
        
        (try! (calculate-and-add-interest tx-sender))
        
        (let ((updated-vault (unwrap! (map-get? vault-balances { parent: tx-sender }) ERR-VAULT-NOT-FOUND)))
            (try! (as-contract (stx-transfer? (get weekly-amount allowance-setting) tx-sender child)))
            
            (map-set vault-balances
                { parent: tx-sender }
                {
                    stx-balance: (- (get stx-balance updated-vault) (get weekly-amount allowance-setting)),
                    last-interest-calc: (get last-interest-calc updated-vault),
                    total-interest-earned: (get total-interest-earned updated-vault),
                    auto-allowance-enabled: (get auto-allowance-enabled updated-vault)
                }
            )
            
            (map-set vault-allowance-settings
                { parent: tx-sender, child: child }
                {
                    weekly-amount: (get weekly-amount allowance-setting),
                    last-distribution: stacks-block-height,
                    total-distributed: (+ (get total-distributed allowance-setting) (get weekly-amount allowance-setting)),
                    active: (get active allowance-setting)
                }
            )
            
            ;; (map-set vault-transactions
            ;;     { parent: tx-sender, tx-id: (var-get next-tx-id) }
            ;;     {
            ;;         transaction-type: "allowance_distribution",
            ;;         amount: (get weekly-amount allowance-setting),
            ;;         timestamp: stacks-block-height,
            ;;         child: (some child)
            ;;     }
            ;; )
            
            (var-set next-tx-id (+ (var-get next-tx-id) u1))
            (ok (get weekly-amount allowance-setting))
        )
    )
)

(define-private (calculate-and-add-interest (parent principal))
    (let ((vault (unwrap! (map-get? vault-balances { parent: parent }) ERR-VAULT-NOT-FOUND)))
        (let (
            (blocks-elapsed (- stacks-block-height (get last-interest-calc vault)))
            (interest-amount (/ (* (get stx-balance vault) (var-get interest-rate) blocks-elapsed) u100000))
        )
            (if (> interest-amount u0)
                (map-set vault-balances
                    { parent: parent }
                    {
                        stx-balance: (+ (get stx-balance vault) interest-amount),
                        last-interest-calc: stacks-block-height,
                        total-interest-earned: (+ (get total-interest-earned vault) interest-amount),
                        auto-allowance-enabled: (get auto-allowance-enabled vault)
                    }
                )
                false
            )
            (ok interest-amount)
        )
    )
)

(define-public (toggle-auto-allowance (child principal) (active bool))
    (let ((allowance-setting (unwrap! (map-get? vault-allowance-settings { parent: tx-sender, child: child }) ERR-VAULT-NOT-FOUND)))
        (ok (map-set vault-allowance-settings
            { parent: tx-sender, child: child }
            {
                weekly-amount: (get weekly-amount allowance-setting),
                last-distribution: (get last-distribution allowance-setting),
                total-distributed: (get total-distributed allowance-setting),
                active: active
            }
        ))
    )
)

(define-read-only (get-vault-balance (parent principal))
    (map-get? vault-balances { parent: parent })
)

(define-read-only (get-allowance-settings (parent principal) (child principal))
    (map-get? vault-allowance-settings { parent: parent, child: child })
)

(define-read-only (get-vault-transaction (parent principal) (tx-id uint))
    (map-get? vault-transactions { parent: parent, tx-id: tx-id })
)

(define-read-only (calculate-projected-interest (parent principal) (blocks uint))
    (let ((vault (map-get? vault-balances { parent: parent })))
        (if (is-some vault)
            (let ((vault-data (unwrap-panic vault)))
                (ok (/ (* (get stx-balance vault-data) (var-get interest-rate) blocks) u100000))
            )
            ERR-VAULT-NOT-FOUND
        )
    )
)

(define-read-only (get-total-family-vault-value (parent principal))
    (let ((vault (map-get? vault-balances { parent: parent })))
        (if (is-some vault)
            (let ((vault-data (unwrap-panic vault)))
                (ok {
                    principal-balance: (get stx-balance vault-data),
                    total-interest-earned: (get total-interest-earned vault-data),
                    total-value: (+ (get stx-balance vault-data) (get total-interest-earned vault-data))
                })
            )
            ERR-VAULT-NOT-FOUND
        )
    )
)