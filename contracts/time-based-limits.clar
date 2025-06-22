;; (define-constant ERR-NOT-AUTHORIZED (err u100))
;; (define-constant ERR-LIMIT-EXCEEDED (err u102))
;; (define-constant ERR-INVALID-TIME-PERIOD (err u103))

;; (define-map time-based-limits
;;     { child: principal, limit-id: uint }
;;     {
;;         limit-type: uint,
;;         amount: uint,
;;         period-blocks: uint,
;;         start-hour: uint,
;;         end-hour: uint,
;;         days-of-week: (list 7 bool),
;;         current-spent: uint,
;;         last-reset: uint,
;;         active: bool
;;     }
;; )

;; (define-map parents principal bool)

;; (define-map child-parent-relationship
;;     { child: principal }
;;     { parent: principal }
;; )

;; (define-map allowances 
;;     { child: principal } 
;;     { amount: uint, parent: principal }
;; )

;; (define-data-var last-limit-id uint u0)

;; (define-public (register-as-parent)
;;     (begin
;;         (map-set parents tx-sender true)
;;         (ok true)
;;     )
;; )

;; (define-public (add-child (child principal))
;;     (begin
;;         (asserts! (default-to false (map-get? parents tx-sender)) ERR-NOT-AUTHORIZED)
;;         (map-set child-parent-relationship { child: child } { parent: tx-sender })
;;         (ok true)
;;     )
;; )

;; (define-public (set-time-based-limit 
;;     (child principal)
;;     (limit-type uint)
;;     (amount uint)
;;     (period-blocks uint)
;;     (start-hour uint)
;;     (end-hour uint)
;;     (days-of-week (list 7 bool))
;; )
;;     (let ((limit-id (+ (var-get last-limit-id) u1)))
;;         (begin
;;             (asserts! (default-to false (map-get? parents tx-sender)) ERR-NOT-AUTHORIZED)
;;             (asserts! (< start-hour u24) ERR-INVALID-TIME-PERIOD)
;;             (asserts! (< end-hour u24) ERR-INVALID-TIME-PERIOD)
;;             (asserts! (> period-blocks u0) ERR-INVALID-TIME-PERIOD)
            
;;             (var-set last-limit-id limit-id)
;;             (map-set time-based-limits
;;                 { child: child, limit-id: limit-id }
;;                 {
;;                     limit-type: limit-type,
;;                     amount: amount,
;;                     period-blocks: period-blocks,
;;                     start-hour: start-hour,
;;                     end-hour: end-hour,
;;                     days-of-week: days-of-week,
;;                     current-spent: u0,
;;                     last-reset: stacks-stacks-block-height,
;;                     active: true
;;                 }
;;             )
;;             (ok limit-id)
;;         )
;;     )
;; )

;; ;; (define-public (spend-with-limits (amount uint))
;; ;;     (let (
;; ;;         (current-allowance (default-to { amount: u0, parent: tx-sender } 
;; ;;             (map-get? allowances { child: tx-sender })))
;; ;;     )
;; ;;         (asserts! (>= (get amount current-allowance) amount) (err u101))
;; ;;         ;; (asserts! (check-all-limits tx-sender amount) ERR-LIMIT-EXCEEDED)
        
;; ;;         (begin
;; ;;             (try! (update-all-limits tx-sender amount))
;; ;;             (map-set allowances
;; ;;                 { child: tx-sender }
;; ;;                 { 
;; ;;                     amount: (- (get amount current-allowance) amount),
;; ;;                     parent: (get parent current-allowance)
;; ;;                 }
;; ;;             )
;; ;;             (ok true)
;; ;;         )
;; ;;     )
;; ;; )

;; (define-public (reset-limit-if-needed (child principal) (limit-id uint))
;;     (let ((limit-data (unwrap! (map-get? time-based-limits { child: child, limit-id: limit-id }) (err u404))))
;;         (if (>= stacks-stacks-block-height (+ (get last-reset limit-data) (get period-blocks limit-data)))
;;             (begin
;;                 (map-set time-based-limits
;;                     { child: child, limit-id: limit-id }
;;                     {
;;                         limit-type: (get limit-type limit-data),
;;                         amount: (get amount limit-data),
;;                         period-blocks: (get period-blocks limit-data),
;;                         start-hour: (get start-hour limit-data),
;;                         end-hour: (get end-hour limit-data),
;;                         days-of-week: (get days-of-week limit-data),
;;                         current-spent: u0,
;;                         last-reset: stacks-stacks-block-height,
;;                         active: (get active limit-data)
;;                     }
;;                 )
;;                 (ok true)
;;             )
;;             (ok false)
;;         )
;;     )
;; )

;; (define-public (toggle-limit (child principal) (limit-id uint) (active bool))
;;     (let ((limit-data (unwrap! (map-get? time-based-limits { child: child, limit-id: limit-id }) (err u404))))
;;         (begin
;;             (asserts! (default-to false (map-get? parents tx-sender)) ERR-NOT-AUTHORIZED)
;;             (map-set time-based-limits
;;                 { child: child, limit-id: limit-id }
;;                 {
;;                     limit-type: (get limit-type limit-data),
;;                     amount: (get amount limit-data),
;;                     period-blocks: (get period-blocks limit-data),
;;                     start-hour: (get start-hour limit-data),
;;                     end-hour: (get end-hour limit-data),
;;                     days-of-week: (get days-of-week limit-data),
;;                     current-spent: (get current-spent limit-data),
;;                     last-reset: (get last-reset limit-data),
;;                     active: active
;;                 }
;;             )
;;             (ok true)
;;         )
;;     )
;; )

;; ;; (define-private (check-all-limits (child principal) (amount uint))
;; ;;     (check-limit-recursive child amount u1 (var-get last-limit-id))
;; ;; )

;; ;; (define-private (check-limit-recursive (child principal) (amount uint) (current-id uint) (max-id uint))
;; ;;     (if (> current-id max-id)
;; ;;         true
;; ;;         (let ((limit-data (map-get? time-based-limits { child: child, limit-id: current-id })))
;; ;;             (if (is-some limit-data)
;; ;;                 (let ((limit (unwrap-panic limit-data)))
;; ;;                     (if (and (get active limit) 
;; ;;                              (is-time-window-active limit)
;; ;;                              (> (+ (get current-spent limit) amount) (get amount limit)))
;; ;;                         false
;; ;;                         (check-limit-recursive child amount (+ current-id u1) max-id)
;; ;;                     )
;; ;;                 )
;; ;;                 (check-limit-recursive child amount (+ current-id u1) max-id)
;; ;;             )
;; ;;         )
;; ;;     )
;; ;; )

;; ;; (define-private (update-all-limits (child principal) (amount uint))
;; ;;     (update-limits-recursive child amount u1 (var-get last-limit-id))
;; ;; )

;; (define-private (update-limits-recursive (child principal) (amount uint) (current-id uint) (max-id uint))
;;     (if (> current-id max-id)
;;         (ok true)
;;         (let ((limit-data (map-get? time-based-limits { child: child, limit-id: current-id })))
;;             (if (is-some limit-data)
;;                 (let ((limit (unwrap-panic limit-data)))
;;                     (if (and (get active limit) (is-time-window-active limit))
;;                         (begin
;;                             (map-set time-based-limits
;;                                 { child: child, limit-id: current-id }
;;                                 {
;;                                     limit-type: (get limit-type limit),
;;                                     amount: (get amount limit),
;;                                     period-blocks: (get period-blocks limit),
;;                                     start-hour: (get start-hour limit),
;;                                     end-hour: (get end-hour limit),
;;                                     days-of-week: (get days-of-week limit),
;;                                     current-spent: (+ (get current-spent limit) amount),
;;                                     last-reset: (get last-reset limit),
;;                                     active: (get active limit)
;;                                 }
;;                             )
;;                             (update-limits-recursive child amount (+ current-id u1) max-id)
;;                         )
;;                         (update-limits-recursive child amount (+ current-id u1) max-id)
;;                     )
;;                 )
;;                 (update-limits-recursive child amount (+ current-id u1) max-id)
;;             )
;;         )
;;     )
;; )

;; (define-private (is-time-window-active (limit-data { limit-type: uint, amount: uint, period-blocks: uint, start-hour: uint, end-hour: uint, days-of-week: (list 7 bool), current-spent: uint, last-reset: uint, active: bool }))
;;     (let ((current-hour (mod (/ stacks-stacks-block-height u6) u24)))
;;         (and 
;;             (>= current-hour (get start-hour limit-data))
;;             (<= current-hour (get end-hour limit-data))
;;         )
;;     )
;; )

;; (define-read-only (get-limit-status (child principal) (limit-id uint))
;;     (let ((limit-data (map-get? time-based-limits { child: child, limit-id: limit-id })))
;;         (if (is-some limit-data)
;;             (let ((limit (unwrap-panic limit-data)))
;;                 (ok {
;;                     remaining: (if (> (get amount limit) (get current-spent limit))
;;                                  (- (get amount limit) (get current-spent limit))
;;                                  u0),
;;                     spent: (get current-spent limit),
;;                     limit: (get amount limit),
;;                     active: (get active limit),
;;                     time-active: (is-time-window-active limit)
;;                 })
;;             )
;;             (err u404)
;;         )
;;     )
;; )

;; (define-read-only (get-all-active-limits (child principal))
;;     (get-active-limits-recursive child u1 (var-get last-limit-id) (list))
;; )

;; (define-private (get-active-limits-recursive (child principal) (current-id uint) (max-id uint) (acc (list 20 uint)))
;;     (if (> current-id max-id)
;;         acc
;;         (let ((limit-data (map-get? time-based-limits { child: child, limit-id: current-id })))
;;             (if (and (is-some limit-data) (get active (unwrap-panic limit-data)))
;;                 (get-active-limits-recursive child (+ current-id u1) max-id (unwrap-panic (as-max-len? (append acc current-id) u20)))
;;                 (get-active-limits-recursive child (+ current-id u1) max-id acc)
;;             )
;;         )
;;     )
;; )

;; (define-read-only (is-parent (address principal))
;;     (default-to false (map-get? parents address))
;; )

;; (define-read-only (get-allowance (child principal))
;;     (default-to { amount: u0, parent: tx-sender }
;;         (map-get? allowances { child: child }))
;; )
