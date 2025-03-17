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


;; Define spending categories
(define-map spending-categories 
    { category-id: uint }
    { 
        name: (string-ascii 30),
        monthly-limit: uint,
        current-spent: uint
    }
)

(define-public (add-category (category-id uint) (name (string-ascii 30)) (limit uint))
    (ok (map-set spending-categories 
        { category-id: category-id }
        { 
            name: name,
            monthly-limit: limit,
            current-spent: u0
        }
    ))
)


(define-data-var parent-address principal tx-sender)
(define-data-var emergency-contact principal tx-sender)
(define-data-var emergency-active bool false)

(define-public (set-emergency-contact (new-contact principal))
    (begin
        (asserts! (is-eq tx-sender (var-get parent-address)) (err u403))
        (ok (var-set emergency-contact new-contact))
    )
)


(define-map reward-points 
    { user: principal }
    { points: uint }
)

(define-public (add-points (amount uint))
    (let ((current-points (default-to u0 (get points (map-get? reward-points { user: tx-sender })))))
        (ok (map-set reward-points
            { user: tx-sender }
            { points: (+ current-points amount) }
        ))
    )
)




(define-map daily-limits
    { user: principal }
    {
        limit: uint,
        spent-today: uint,
        last-reset: uint
    }
)

(define-public (set-daily-limit (amount uint))
    (ok (map-set daily-limits
        { user: tx-sender }
        {
            limit: amount,
            spent-today: u0,
            last-reset: stacks-block-height
        }
    ))
)



(define-map financial-quizzes
    { quiz-id: uint }
    {
        question: (string-ascii 100),
        correct-answer: (string-ascii 50),
        points: uint
    }
)

(define-public (complete-quiz (quiz-id uint) (answer (string-ascii 50)))
    (let ((quiz (unwrap! (map-get? financial-quizzes { quiz-id: quiz-id }) (err u404))))
        (if (is-eq (get correct-answer quiz) answer)
            (add-points (get points quiz))
            (err u401)
        )
    )
)



(define-data-var last-chore-id uint u0)

(define-map chores
    { chore-id: uint }
    {
        name: (string-ascii 50),
        reward: uint,
        assigned-to: principal,
        completed: bool
    }
)

(define-public (add-chore (name (string-ascii 50)) (reward uint) (assigned-to principal))
    (let ((chore-id (+ (var-get last-chore-id) u1)))
        (ok (map-set chores
            { chore-id: chore-id }
            {
                name: name,
                reward: reward,
                assigned-to: assigned-to,
                completed: false
            }
        ))
    )
)


;; Savings Goals Feature
(define-data-var last-goal-id uint u0)

(define-map savings-goals
    { goal-id: uint }
    {
        child: principal,
        name: (string-ascii 50),
        target-amount: uint,
        current-amount: uint,
        completed: bool
    }
)

(define-public (create-savings-goal (name (string-ascii 50)) (target-amount uint))
    (let ((goal-id (+ (var-get last-goal-id) u1)))
        (begin
            (var-set last-goal-id goal-id)
            (ok (map-set savings-goals
                { goal-id: goal-id }
                {
                    child: tx-sender,
                    name: name,
                    target-amount: target-amount,
                    current-amount: u0,
                    completed: false
                }
            ))
        )
    )
)

(define-public (contribute-to-goal (goal-id uint) (amount uint))
    (let (
        (goal (unwrap! (map-get? savings-goals { goal-id: goal-id }) (err u404)))
        (allowance (get-allowance tx-sender))
    )
        (asserts! (is-eq (get child goal) tx-sender) (err u403))
        (asserts! (>= (get amount allowance) amount) ERR-INSUFFICIENT-BALANCE)
        
        (let ((new-amount (+ (get current-amount goal) amount))
              (is-completed (>= new-amount (get target-amount goal))))
            (begin
                ;; Update allowance
                (map-set allowances 
                    { child: tx-sender }
                    { amount: (- (get amount allowance) amount),
                      parent: (get parent allowance) })
                
                ;; Update goal
                (map-set savings-goals
                    { goal-id: goal-id }
                    {
                        child: tx-sender,
                        name: (get name goal),
                        target-amount: (get target-amount goal),
                        current-amount: new-amount,
                        completed: is-completed
                    }
                )
                (ok is-completed)
            )
        )
    )
)

(define-read-only (get-savings-goal (goal-id uint))
    (map-get? savings-goals { goal-id: goal-id })
)


;; Allowance Schedule Feature
(define-map allowance-schedules
    { child: principal }
    {
        amount: uint,
        frequency: uint, ;; in blocks (e.g., ~144 blocks per day on Stacks)
        last-payment: uint,
        active: bool
    }
)

(define-public (set-allowance-schedule (child principal) (amount uint) (frequency uint))
    (begin
        (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set allowance-schedules
            { child: child }
            {
                amount: amount,
                frequency: frequency,
                last-payment: stacks-block-height,
                active: true
            }
        ))
    )
)

(define-public (process-scheduled-allowance (child principal))
    (let (
        (schedule (unwrap! (map-get? allowance-schedules { child: child }) (err u404)))
        (current-allowance (get-allowance child))
    )
        (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (get active schedule) (err u405))
        (asserts! (>= stacks-block-height (+ (get last-payment schedule) (get frequency schedule))) (err u406))
        
        (begin
            ;; Update allowance
            (map-set allowances 
                { child: child }
                { amount: (+ (get amount current-allowance) (get amount schedule)),
                  parent: tx-sender })
            
            ;; Update last payment time
            (map-set allowance-schedules
                { child: child }
                {
                    amount: (get amount schedule),
                    frequency: (get frequency schedule),
                    last-payment: stacks-block-height,
                    active: true
                }
            )
            (ok true)
        )
    )
)

(define-public (toggle-allowance-schedule (child principal) (active bool))
    (let ((schedule (unwrap! (map-get? allowance-schedules { child: child }) (err u404))))
        (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set allowance-schedules
            { child: child }
            {
                amount: (get amount schedule),
                frequency: (get frequency schedule),
                last-payment: (get last-payment schedule),
                active: active
            }
        ))
    )
)



;; Spending Approval System
(define-data-var last-request-id uint u0)

(define-map approval-thresholds
    { child: principal }
    { threshold: uint }
)

(define-map spending-requests
    { request-id: uint }
    {
        child: principal,
        amount: uint,
        description: (string-ascii 100),
        status: (string-ascii 10), ;; "pending", "approved", "rejected"
        timestamp: uint
    }
)

(define-public (set-approval-threshold (child principal) (threshold uint))
    (begin
        (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set approval-thresholds
            { child: child }
            { threshold: threshold }
        ))
    )
)

(define-public (request-spending (amount uint) (description (string-ascii 100)))
    (let (
        (request-id (+ (var-get last-request-id) u1))
        (threshold (default-to { threshold: u0 } (map-get? approval-thresholds { child: tx-sender })))
    )
        (begin
            (var-set last-request-id request-id)
            ;; If amount is below threshold, auto-approve
            (if (< amount (get threshold threshold))
                (spend amount)
                (ok (map-set spending-requests
                    { request-id: request-id }
                    {
                        child: tx-sender,
                        amount: amount,
                        description: description,
                        status: "pending",
                        timestamp: stacks-block-height
                    }
                ))
            )
        )
    )
)

(define-public (approve-spending-request (request-id uint))
    (let ((request (unwrap! (map-get? spending-requests { request-id: request-id }) (err u404))))
        (begin
            (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
            (asserts! (is-eq (get status request) "pending") (err u407))
            
            ;; Update request status
            (map-set spending-requests
                { request-id: request-id }
                {
                    child: (get child request),
                    amount: (get amount request),
                    description: (get description request),
                    status: "approved",
                    timestamp: (get timestamp request)
                }
            )
            
            ;; Process the spending
            (as-contract (spend-as-child (get child request) (get amount request)))
        )
    )
)

(define-public (reject-spending-request (request-id uint))
    (let ((request (unwrap! (map-get? spending-requests { request-id: request-id }) (err u404))))
        (begin
            (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
            (asserts! (is-eq (get status request) "pending") (err u407))
            
            (ok (map-set spending-requests
                { request-id: request-id }
                {
                    child: (get child request),
                    amount: (get amount request),
                    description: (get description request),
                    status: "rejected",
                    timestamp: (get timestamp request)
                }
            ))
        )
    )
)

;; Helper function to spend on behalf of a child
(define-private (spend-as-child (child principal) (amount uint))
    (let ((allowance (get-allowance child)))
        (if (>= (get amount allowance) amount)
            (begin
                (map-set allowances 
                    { child: child }
                    { amount: (- (get amount allowance) amount),
                      parent: (get parent allowance) })
                (ok true))
            ERR-INSUFFICIENT-BALANCE)))


;; Financial Education Module
(define-data-var last-lesson-id uint u0)

(define-map financial-lessons
    { lesson-id: uint }
    {
        title: (string-ascii 50),
        content-hash: (string-ascii 64), ;; IPFS hash to lesson content
        quiz-id: uint,
        points: uint,
        difficulty: uint ;; 1-5 scale
    }
)

(define-map completed-lessons
    { user: principal, lesson-id: uint }
    {
        completed: bool,
        score: uint,
        timestamp: uint
    }
)

(define-public (add-financial-lesson (title (string-ascii 50)) 
                                    (content-hash (string-ascii 64)) 
                                    (quiz-id uint) 
                                    (points uint)
                                    (difficulty uint))
    (let ((lesson-id (+ (var-get last-lesson-id) u1)))
        (begin
            (asserts! (is-parent tx-sender) ERR-NOT-AUTHORIZED)
            (asserts! (<= difficulty u5) (err u408))
            (var-set last-lesson-id lesson-id)
            (ok (map-set financial-lessons
                { lesson-id: lesson-id }
                {
                    title: title,
                    content-hash: content-hash,
                    quiz-id: quiz-id,
                    points: points,
                    difficulty: difficulty
                }
            ))
        )
    )
)

(define-public (complete-lesson (lesson-id uint) (score uint))
    (let ((lesson (unwrap! (map-get? financial-lessons { lesson-id: lesson-id }) (err u404))))
        (begin
            ;; Record completion
            (map-set completed-lessons
                { user: tx-sender, lesson-id: lesson-id }
                {
                    completed: true,
                    score: score,
                    timestamp: stacks-block-height
                }
            )
            
            ;; Award points based on score percentage
            (let ((earned-points (/ (* (get points lesson) score) u100)))
                (add-points earned-points)
            )
        )
    )
)

(define-read-only (get-lesson (lesson-id uint))
    (map-get? financial-lessons { lesson-id: lesson-id })
)

(define-read-only (get-lesson-completion (user principal) (lesson-id uint))
    (map-get? completed-lessons { user: user, lesson-id: lesson-id })
)


;; Parent-Child Messaging System
(define-data-var last-message-id uint u0)

(define-map messages
    { message-id: uint }
    {
        sender: principal,
        recipient: principal,
        content: (string-ascii 280),
        timestamp: uint,
        read: bool
    }
)

(define-public (send-message (recipient principal) (content (string-ascii 280)))
    (let ((message-id (+ (var-get last-message-id) u1)))
        (begin
            (var-set last-message-id message-id)
            (ok (map-set messages
                { message-id: message-id }
                {
                    sender: tx-sender,
                    recipient: recipient,
                    content: content,
                    timestamp: stacks-block-height,
                    read: false
                }
            ))
        )
    )
)

(define-public (mark-message-read (message-id uint))
    (let ((message (unwrap! (map-get? messages { message-id: message-id }) (err u404))))
        (begin
            (asserts! (is-eq tx-sender (get recipient message)) (err u403))
            (ok (map-set messages
                { message-id: message-id }
                {
                    sender: (get sender message),
                    recipient: (get recipient message),
                    content: (get content message),
                    timestamp: (get timestamp message),
                    read: true
                }
            ))
        )
    )
)

(define-read-only (get-message (message-id uint))
    (map-get? messages { message-id: message-id })
)

(define-read-only (is-message-recipient (message-id uint) (user principal))
    (let ((message (map-get? messages { message-id: message-id })))
        (if (is-some message)
            (ok (is-eq user (get recipient (unwrap-panic message))))
            (ok false)
        )
    )
)


