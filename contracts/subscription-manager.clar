;; Digital Allowance Subscription & Recurring Payment Manager
;; Enables children to subscribe to digital services with parental oversight

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BUDGET (err u101))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u102))
(define-constant ERR-SERVICE-NOT-FOUND (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-SUBSCRIPTION-INACTIVE (err u105))
(define-constant ERR-ALREADY-SUBSCRIBED (err u106))

;; Data variables
(define-data-var next-subscription-id uint u1)
(define-data-var next-service-id uint u1)

;; Digital service catalog
(define-map digital-services
    { service-id: uint }
    {
        name: (string-ascii 50),
        provider: (string-ascii 30),
        monthly-cost: uint,
        category: (string-ascii 20),
        requires-approval: bool,
        age-restriction: uint,
        active: bool
    }
)

;; Child subscriptions
(define-map child-subscriptions
    { subscription-id: uint }
    {
        child: principal,
        service-id: uint,
        parent: principal,
        monthly-budget: uint,
        status: (string-ascii 10), ;; "pending", "active", "paused", "cancelled"
        start-date: uint,
        next-payment: uint,
        total-spent: uint,
        auto-renew: bool
    }
)

;; Subscription budgets allocated by parents
(define-map subscription-budgets
    { child: principal, service-id: uint }
    {
        allocated-amount: uint,
        used-amount: uint,
        renewal-date: uint,
        budget-alerts: bool
    }
)

;; Family subscription sharing
(define-map family-subscriptions
    { family-id: uint }
    {
        service-id: uint,
        owner-parent: principal,
        shared-children: (list 5 principal),
        total-cost: uint,
        cost-per-child: uint,
        active: bool
    }
)

;; Payment history for subscriptions
(define-map payment-history
    { subscription-id: uint, payment-id: uint }
    {
        amount: uint,
        timestamp: uint,
        payment-status: (string-ascii 10), ;; "success", "failed", "pending"
        budget-source: (string-ascii 20)
    }
)

;; Add new digital service to catalog
(define-public (add-digital-service 
    (name (string-ascii 50))
    (provider (string-ascii 30))
    (monthly-cost uint)
    (category (string-ascii 20))
    (requires-approval bool)
    (age-restriction uint))
    
    (let ((service-id (var-get next-service-id)))
        (begin
            (asserts! (> monthly-cost u0) ERR-INVALID-AMOUNT)
            (asserts! (> (len name) u0) ERR-INVALID-AMOUNT)
            
            (map-set digital-services
                { service-id: service-id }
                {
                    name: name,
                    provider: provider,
                    monthly-cost: monthly-cost,
                    category: category,
                    requires-approval: requires-approval,
                    age-restriction: age-restriction,
                    active: true
                }
            )
            (var-set next-service-id (+ service-id u1))
            (ok service-id)
        )
    )
)

;; Child requests subscription to a service
(define-public (request-subscription (service-id uint) (monthly-budget uint))
    (let ((service (unwrap! (map-get? digital-services { service-id: service-id }) ERR-SERVICE-NOT-FOUND))
          (subscription-id (var-get next-subscription-id)))
        
        (asserts! (get active service) ERR-SERVICE-NOT-FOUND)
        (asserts! (>= monthly-budget (get monthly-cost service)) ERR-INSUFFICIENT-BUDGET)
        
        (map-set child-subscriptions
            { subscription-id: subscription-id }
            {
                child: tx-sender,
                service-id: service-id,
                parent: tx-sender, ;; Will be updated when parent approves
                monthly-budget: monthly-budget,
                status: (if (get requires-approval service) "pending" "active"),
                start-date: stacks-block-height,
                next-payment: (+ stacks-block-height u4320), ;; ~30 days
                total-spent: u0,
                auto-renew: true
            }
        )
        
        (var-set next-subscription-id (+ subscription-id u1))
        (ok subscription-id)
    )
)

;; Parent approves subscription request
(define-public (approve-subscription (subscription-id uint) (approved-budget uint))
    (let ((subscription (unwrap! (map-get? child-subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND)))
        
        (asserts! (is-eq (get status subscription) "pending") ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (>= approved-budget (get monthly-cost (unwrap-panic (map-get? digital-services { service-id: (get service-id subscription) })))) ERR-INSUFFICIENT-BUDGET)
        
        (map-set child-subscriptions
            { subscription-id: subscription-id }
            (merge subscription {
                parent: tx-sender,
                monthly-budget: approved-budget,
                status: "active"
            })
        )
        
        ;; Set up subscription budget
        (map-set subscription-budgets
            { child: (get child subscription), service-id: (get service-id subscription) }
            {
                allocated-amount: approved-budget,
                used-amount: u0,
                renewal-date: (+ stacks-block-height u4320),
                budget-alerts: true
            }
        )
        
        (ok true)
    )
)

;; Process recurring payment for active subscription
(define-public (process-recurring-payment (subscription-id uint))
    (let ((subscription (unwrap! (map-get? child-subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
          (service (unwrap! (map-get? digital-services { service-id: (get service-id subscription) }) ERR-SERVICE-NOT-FOUND))
          (budget (unwrap! (map-get? subscription-budgets { child: (get child subscription), service-id: (get service-id subscription) }) ERR-INSUFFICIENT-BUDGET)))
        
        (asserts! (is-eq (get status subscription) "active") ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (>= stacks-block-height (get next-payment subscription)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (- (get allocated-amount budget) (get used-amount budget)) (get monthly-cost service)) ERR-INSUFFICIENT-BUDGET)
        
        (let ((payment-amount (get monthly-cost service)))
            (begin
                ;; Update subscription
                (map-set child-subscriptions
                    { subscription-id: subscription-id }
                    (merge subscription {
                        next-payment: (+ (get next-payment subscription) u4320),
                        total-spent: (+ (get total-spent subscription) payment-amount)
                    })
                )
                
                ;; Update budget usage
                (map-set subscription-budgets
                    { child: (get child subscription), service-id: (get service-id subscription) }
                    (merge budget {
                        used-amount: (+ (get used-amount budget) payment-amount)
                    })
                )
                
                ;; Record payment
                (map-set payment-history
                    { subscription-id: subscription-id, payment-id: (get total-spent subscription) }
                    {
                        amount: payment-amount,
                        timestamp: stacks-block-height,
                        payment-status: "success",
                        budget-source: "monthly-budget"
                    }
                )
                
                (ok payment-amount)
            )
        )
    )
)

;; Create family subscription for multiple children
(define-public (create-family-subscription 
    (service-id uint) 
    (shared-children (list 5 principal))
    (total-monthly-budget uint))
    
    (let ((service (unwrap! (map-get? digital-services { service-id: service-id }) ERR-SERVICE-NOT-FOUND))
          (family-id (var-get next-subscription-id))
          (cost-per-child (/ total-monthly-budget (len shared-children))))
        
        (asserts! (get active service) ERR-SERVICE-NOT-FOUND)
        (asserts! (>= total-monthly-budget (get monthly-cost service)) ERR-INSUFFICIENT-BUDGET)
        (asserts! (> (len shared-children) u1) ERR-INVALID-AMOUNT)
        
        (map-set family-subscriptions
            { family-id: family-id }
            {
                service-id: service-id,
                owner-parent: tx-sender,
                shared-children: shared-children,
                total-cost: total-monthly-budget,
                cost-per-child: cost-per-child,
                active: true
            }
        )
        
        (var-set next-subscription-id (+ family-id u1))
        (ok family-id)
    )
)

;; Pause or cancel subscription
(define-public (update-subscription-status (subscription-id uint) (new-status (string-ascii 10)))
    (let ((subscription (unwrap! (map-get? child-subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND)))
        
        (asserts! (or (is-eq tx-sender (get parent subscription)) (is-eq tx-sender (get child subscription))) ERR-NOT-AUTHORIZED)
        
        (map-set child-subscriptions
            { subscription-id: subscription-id }
            (merge subscription { status: new-status })
        )
        (ok true)
    )
)

;; Renew subscription budget (monthly reset)
(define-public (renew-subscription-budget (child principal) (service-id uint) (new-budget uint))
    (let ((budget (unwrap! (map-get? subscription-budgets { child: child, service-id: service-id }) ERR-SUBSCRIPTION-NOT-FOUND)))
        
        (asserts! (>= stacks-block-height (get renewal-date budget)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-budget u0) ERR-INVALID-AMOUNT)
        
        (map-set subscription-budgets
            { child: child, service-id: service-id }
            {
                allocated-amount: new-budget,
                used-amount: u0,
                renewal-date: (+ stacks-block-height u4320),
                budget-alerts: (get budget-alerts budget)
            }
        )
        (ok new-budget)
    )
)

;; Toggle auto-renewal for subscription
(define-public (toggle-auto-renewal (subscription-id uint) (auto-renew bool))
    (let ((subscription (unwrap! (map-get? child-subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND)))
        
        (asserts! (is-eq tx-sender (get child subscription)) ERR-NOT-AUTHORIZED)
        
        (map-set child-subscriptions
            { subscription-id: subscription-id }
            (merge subscription { auto-renew: auto-renew })
        )
        (ok auto-renew)
    )
)

;; Read-only functions
(define-read-only (get-digital-service (service-id uint))
    (map-get? digital-services { service-id: service-id })
)

(define-read-only (get-child-subscription (subscription-id uint))
    (map-get? child-subscriptions { subscription-id: subscription-id })
)

(define-read-only (get-subscription-budget (child principal) (service-id uint))
    (map-get? subscription-budgets { child: child, service-id: service-id })
)

(define-read-only (get-family-subscription (family-id uint))
    (map-get? family-subscriptions { family-id: family-id })
)

(define-read-only (get-payment-history (subscription-id uint) (payment-id uint))
    (map-get? payment-history { subscription-id: subscription-id, payment-id: payment-id })
)

;; Get subscription summary for a child
(define-read-only (get-child-subscription-summary (child principal))
    (let ((active-count u0) ;; Simplified - would count active subscriptions in full implementation
          (total-monthly-cost u0) ;; Would calculate total monthly costs
          (pending-count u0)) ;; Would count pending approvals
        {
            active-subscriptions: active-count,
            total-monthly-spend: total-monthly-cost,
            pending-approvals: pending-count,
            budget-utilization: u75 ;; Example percentage
        }
    )
)
