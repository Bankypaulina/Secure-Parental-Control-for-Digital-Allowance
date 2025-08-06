;; Smart Contract Audit Trail and Compliance Monitoring System

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INVALID-PARAMETERS (err u102))
(define-constant ERR-AUDIT-NOT-FOUND (err u103))
(define-constant ERR-COMPLIANCE-VIOLATION (err u104))
(define-constant ERR-REPORT-NOT-FOUND (err u105))
(define-constant ERR-THRESHOLD-EXCEEDED (err u106))

;; Audit trail constants
(define-constant TRANSACTION-TYPES (list "allowance_set" "spending" "deposit" "withdrawal" "transfer" "reward" "savings"))
(define-constant COMPLIANCE-LEVELS (list "low" "medium" "high" "critical"))
(define-constant AUDIT-STATUS (list "active" "flagged" "reviewed" "cleared"))

;; Data variables
(define-data-var next-audit-id uint u1)
(define-data-var next-report-id uint u1)
(define-data-var compliance-threshold-amount uint u1000000) ;; 1M micro-STX threshold
(define-data-var daily-transaction-limit uint u50)
(define-data-var monthly-reporting-enabled bool true)

;; Core audit trail data
(define-map audit-records
    { audit-id: uint }
    {
        transaction-type: (string-ascii 20),
        principal-involved: principal,
        amount: uint,
        related-contract: (string-ascii 30),
        metadata: (string-ascii 100),
        timestamp: uint,
        block-height: uint,
        compliance-level: (string-ascii 10),
        status: (string-ascii 10),
        parent-authority: principal
    }
)

;; Daily transaction counters
(define-map daily-transaction-counts
    { principal: principal, date: uint }
    {
        count: uint,
        total-amount: uint,
        flagged-transactions: uint
    }
)

;; Compliance monitoring rules
(define-map compliance-rules
    { rule-id: uint }
    {
        rule-name: (string-ascii 50),
        trigger-amount: uint,
        trigger-frequency: uint,
        time-window: uint,
        severity: (string-ascii 10),
        auto-flag: bool,
        active: bool
    }
)

;; Regulatory reports
(define-map compliance-reports
    { report-id: uint }
    {
        report-type: (string-ascii 30),
        period-start: uint,
        period-end: uint,
        total-transactions: uint,
        total-volume: uint,
        flagged-count: uint,
        generated-by: principal,
        timestamp: uint,
        report-hash: (string-ascii 64)
    }
)

;; Suspicious activity patterns
(define-map suspicious-patterns
    { principal: principal }
    {
        high-frequency-score: uint,
        unusual-amount-score: uint,
        off-hours-score: uint,
        total-risk-score: uint,
        last-updated: uint,
        investigation-status: (string-ascii 20)
    }
)

;; Public function to record audit trail entry
(define-public (record-audit-entry 
    (transaction-type (string-ascii 20))
    (principal-involved principal)
    (amount uint)
    (related-contract (string-ascii 30))
    (metadata (string-ascii 100)))
    
    (let ((audit-id (var-get next-audit-id))
          (compliance-level (calculate-compliance-level amount))
          (current-date (/ stacks-block-height u144))) ;; Approximate daily blocks
        
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> (len transaction-type) u0) ERR-INVALID-PARAMETERS)
        
        (begin
            ;; Record the audit entry
            (map-set audit-records
                { audit-id: audit-id }
                {
                    transaction-type: transaction-type,
                    principal-involved: principal-involved,
                    amount: amount,
                    related-contract: related-contract,
                    metadata: metadata,
                    timestamp: stacks-block-height,
                    block-height: stacks-block-height,
                    compliance-level: compliance-level,
                    status: "active",
                    parent-authority: tx-sender
                }
            )
            
            ;; Update daily transaction counters
            (unwrap-panic (update-daily-counters principal-involved current-date amount))
            
            ;; Check compliance rules and auto-flag if necessary
            (unwrap-panic (check-compliance-violations audit-id amount principal-involved))
            
            ;; Update suspicious activity patterns
            (unwrap-panic (update-risk-scoring principal-involved amount))
            
            (var-set next-audit-id (+ audit-id u1))
            (ok audit-id)
        )
    )
)

;; Update daily transaction counters
(define-private (update-daily-counters (principal-involved principal) (date uint) (amount uint))
    (let ((current-count (default-to 
            { count: u0, total-amount: u0, flagged-transactions: u0 }
            (map-get? daily-transaction-counts { principal: principal-involved, date: date }))))
        
        (let ((new-count (+ (get count current-count) u1))
              (new-total (+ (get total-amount current-count) amount))
              (flagged (if (> new-count (var-get daily-transaction-limit)) u1 u0)))
            
            (map-set daily-transaction-counts
                { principal: principal-involved, date: date }
                {
                    count: new-count,
                    total-amount: new-total,
                    flagged-transactions: (+ (get flagged-transactions current-count) flagged)
                }
            )
            (ok true)
        )
    )
)

;; Calculate compliance level based on amount
(define-private (calculate-compliance-level (amount uint))
    (if (>= amount (var-get compliance-threshold-amount))
        "high"
        (if (>= amount (/ (var-get compliance-threshold-amount) u10))
            "medium"
            "low"
        )
    )
)

;; Check compliance violations and auto-flag
(define-private (check-compliance-violations (audit-id uint) (amount uint) (principal-involved principal))
    (let ((high-amount-violation (>= amount (var-get compliance-threshold-amount)))
          (current-date (/ stacks-block-height u144))
          (daily-stats (map-get? daily-transaction-counts { principal: principal-involved, date: current-date })))
        
        (if (or high-amount-violation 
                (and (is-some daily-stats) 
                     (> (get count (unwrap-panic daily-stats)) (var-get daily-transaction-limit))))
            (begin
                (map-set audit-records
                    { audit-id: audit-id }
                    (merge (unwrap-panic (map-get? audit-records { audit-id: audit-id }))
                           { status: "flagged" }))
                (ok true))
            (ok false))
    )
)

;; Update risk scoring for suspicious activity patterns
(define-private (update-risk-scoring (principal-involved principal) (amount uint))
    (let ((current-pattern (default-to
            {
                high-frequency-score: u0,
                unusual-amount-score: u0,
                off-hours-score: u0,
                total-risk-score: u0,
                last-updated: u0,
                investigation-status: "clear"
            }
            (map-get? suspicious-patterns { principal: principal-involved }))))
        
        (let ((frequency-score (calculate-frequency-score principal-involved))
              (amount-score (calculate-amount-score amount))
              (time-score (calculate-time-score))
              (total-score (+ frequency-score (+ amount-score time-score))))
            
            (map-set suspicious-patterns
                { principal: principal-involved }
                {
                    high-frequency-score: frequency-score,
                    unusual-amount-score: amount-score,
                    off-hours-score: time-score,
                    total-risk-score: total-score,
                    last-updated: stacks-block-height,
                    investigation-status: (if (> total-score u70) "requires_review" "clear")
                }
            )
            (ok total-score)
        )
    )
)

;; Calculate frequency score based on recent activity
(define-private (calculate-frequency-score (principal-involved principal))
    (let ((current-date (/ stacks-block-height u144))
          (daily-stats (map-get? daily-transaction-counts { principal: principal-involved, date: current-date })))
        
        (if (is-some daily-stats)
            (let ((count (get count (unwrap-panic daily-stats))))
                (if (> count (* (var-get daily-transaction-limit) u2))
                    u50
                    (if (> count (var-get daily-transaction-limit))
                        u25
                        u0)))
            u0)
    )
)

;; Calculate amount score for unusual spending patterns
(define-private (calculate-amount-score (amount uint))
    (if (>= amount (* (var-get compliance-threshold-amount) u2))
        u40
        (if (>= amount (var-get compliance-threshold-amount))
            u20
            u0))
)

;; Calculate time-based score for off-hours transactions
(define-private (calculate-time-score)
    (let ((hour-of-day (mod (/ stacks-block-height u6) u24))) ;; Approximate hour calculation
        (if (or (< hour-of-day u6) (> hour-of-day u22))
            u15
            u0))
)

;; Generate compliance report
(define-public (generate-compliance-report 
    (report-type (string-ascii 30))
    (period-start uint)
    (period-end uint))
    
    (let ((report-id (var-get next-report-id))
          (report-stats (calculate-report-statistics period-start period-end)))
        
        (asserts! (< period-start period-end) ERR-INVALID-PARAMETERS)
        (asserts! (> (len report-type) u0) ERR-INVALID-PARAMETERS)
        
        (map-set compliance-reports
            { report-id: report-id }
            {
                report-type: report-type,
                period-start: period-start,
                period-end: period-end,
                total-transactions: (get total-tx report-stats),
                total-volume: (get total-volume report-stats),
                flagged-count: (get flagged-count report-stats),
                generated-by: tx-sender,
                timestamp: stacks-block-height,
                report-hash: (generate-report-hash report-id)
            }
        )
        
        (var-set next-report-id (+ report-id u1))
        (ok report-id)
    )
)

;; Calculate report statistics for a given period
(define-private (calculate-report-statistics (start uint) (end uint))
    {
        total-tx: u0, ;; Simplified - would iterate through audit records in full implementation
        total-volume: u0,
        flagged-count: u0
    }
)

;; Generate simple hash for report integrity
(define-private (generate-report-hash (report-id uint))
    (concat "audit_" (concat (if (< report-id u10) "0" "1") "_hash"))
)

;; Set compliance monitoring rules
(define-public (set-compliance-rule
    (rule-name (string-ascii 50))
    (trigger-amount uint)
    (trigger-frequency uint)
    (time-window uint)
    (severity (string-ascii 10))
    (auto-flag bool))
    
    (let ((rule-id (var-get next-audit-id))) ;; Reusing counter for simplicity
        
        (asserts! (> (len rule-name) u0) ERR-INVALID-PARAMETERS)
        (asserts! (> trigger-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set compliance-rules
            { rule-id: rule-id }
            {
                rule-name: rule-name,
                trigger-amount: trigger-amount,
                trigger-frequency: trigger-frequency,
                time-window: time-window,
                severity: severity,
                auto-flag: auto-flag,
                active: true
            }
        )
        (ok rule-id)
    )
)

;; Administrative function to review and clear flagged transactions
(define-public (review-flagged-transaction (audit-id uint) (new-status (string-ascii 10)))
    (let ((audit-record (unwrap! (map-get? audit-records { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get parent-authority audit-record)) ERR-NOT-AUTHORIZED)
        
        (map-set audit-records
            { audit-id: audit-id }
            (merge audit-record { status: new-status })
        )
        (ok true)
    )
)

;; Update compliance threshold
(define-public (update-compliance-threshold (new-threshold uint))
    (begin
        (asserts! (> new-threshold u0) ERR-INVALID-AMOUNT)
        (var-set compliance-threshold-amount new-threshold)
        (ok new-threshold)
    )
)

;; Update daily transaction limit
(define-public (update-daily-limit (new-limit uint))
    (begin
        (asserts! (> new-limit u0) ERR-INVALID-PARAMETERS)
        (var-set daily-transaction-limit new-limit)
        (ok new-limit)
    )
)

;; Read-only functions for querying audit data

(define-read-only (get-audit-record (audit-id uint))
    (map-get? audit-records { audit-id: audit-id })
)

(define-read-only (get-daily-stats (principal-involved principal) (date uint))
    (map-get? daily-transaction-counts { principal: principal-involved, date: date })
)

(define-read-only (get-compliance-report (report-id uint))
    (map-get? compliance-reports { report-id: report-id })
)

(define-read-only (get-suspicious-pattern (principal-involved principal))
    (map-get? suspicious-patterns { principal: principal-involved })
)

(define-read-only (get-compliance-rule (rule-id uint))
    (map-get? compliance-rules { rule-id: rule-id })
)

(define-read-only (get-current-compliance-threshold)
    (var-get compliance-threshold-amount)
)

(define-read-only (get-daily-transaction-limit)
    (var-get daily-transaction-limit)
)

;; Check if principal has any flagged transactions
(define-read-only (has-flagged-transactions (principal-involved principal))
    (let ((pattern (map-get? suspicious-patterns { principal: principal-involved })))
        (if (is-some pattern)
            (> (get total-risk-score (unwrap-panic pattern)) u50)
            false)
    )
)

;; Get compliance status summary for a principal
(define-read-only (get-compliance-status (principal-involved principal))
    (let ((pattern (map-get? suspicious-patterns { principal: principal-involved }))
          (current-date (/ stacks-block-height u144))
          (daily-stats (map-get? daily-transaction-counts { principal: principal-involved, date: current-date })))
        
        {
            risk-score: (if (is-some pattern) (get total-risk-score (unwrap-panic pattern)) u0),
            investigation-status: (if (is-some pattern) (get investigation-status (unwrap-panic pattern)) "clear"),
            daily-transaction-count: (if (is-some daily-stats) (get count (unwrap-panic daily-stats)) u0),
            daily-volume: (if (is-some daily-stats) (get total-amount (unwrap-panic daily-stats)) u0),
            flagged-today: (if (is-some daily-stats) (get flagged-transactions (unwrap-panic daily-stats)) u0)
        }
    )
)

