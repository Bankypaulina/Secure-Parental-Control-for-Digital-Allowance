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
