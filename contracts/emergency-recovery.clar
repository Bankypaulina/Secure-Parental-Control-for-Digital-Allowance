(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-GUARDIAN (err u101))
(define-constant ERR-INSUFFICIENT-SIGNATURES (err u102))
(define-constant ERR-RECOVERY-NOT-FOUND (err u103))
(define-constant ERR-RECOVERY-EXPIRED (err u104))
(define-constant ERR-ALREADY-EXECUTED (err u105))
(define-constant ERR-INVALID-TIME (err u106))

(define-map family-recovery-setup
    { family-owner: principal }
    {
        guardians: (list 5 principal),
        required-signatures: uint,
        recovery-delay-blocks: uint,
        active: bool
    }
)

(define-map recovery-requests
    { request-id: uint }
    {
        family-owner: principal,
        new-owner: principal,
        signatures: (list 5 principal),
        created-at: uint,
        expires-at: uint,
        executed: bool
    }
)

(define-map guardian-signatures
    { request-id: uint, guardian: principal }
    { signed: bool, timestamp: uint }
)

(define-data-var next-request-id uint u1)

(define-public (setup-family-recovery 
    (guardians (list 5 principal)) 
    (required-signatures uint) 
    (recovery-delay-blocks uint))
    (begin
        (asserts! (> required-signatures u0) ERR-INVALID-GUARDIAN)
        (asserts! (<= required-signatures (len guardians)) ERR-INVALID-GUARDIAN)
        (asserts! (> recovery-delay-blocks u144) ERR-INVALID-TIME)
        
        (map-set family-recovery-setup
            { family-owner: tx-sender }
            {
                guardians: guardians,
                required-signatures: required-signatures,
                recovery-delay-blocks: recovery-delay-blocks,
                active: true
            }
        )
        (ok true)
    )
)

(define-public (initiate-recovery (family-owner principal) (new-owner principal))
    (let (
        (setup (unwrap! (map-get? family-recovery-setup { family-owner: family-owner }) ERR-RECOVERY-NOT-FOUND))
        (request-id (var-get next-request-id))
    )
        (asserts! (get active setup) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (index-of (get guardians setup) tx-sender)) ERR-NOT-AUTHORIZED)
        
        (map-set recovery-requests
            { request-id: request-id }
            {
                family-owner: family-owner,
                new-owner: new-owner,
                signatures: (list),
                created-at: stacks-block-height,
                expires-at: (+ stacks-block-height (get recovery-delay-blocks setup)),
                executed: false
            }
        )
        
        (var-set next-request-id (+ request-id u1))
        (ok request-id)
    )
)

(define-public (sign-recovery (request-id uint))
    (let (
        (request (unwrap! (map-get? recovery-requests { request-id: request-id }) ERR-RECOVERY-NOT-FOUND))
        (setup (unwrap! (map-get? family-recovery-setup { family-owner: (get family-owner request) }) ERR-RECOVERY-NOT-FOUND))
        (existing-signature (map-get? guardian-signatures { request-id: request-id, guardian: tx-sender }))
    )
        (asserts! (get active setup) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (index-of (get guardians setup) tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (<= stacks-block-height (get expires-at request)) ERR-RECOVERY-EXPIRED)
        (asserts! (not (get executed request)) ERR-ALREADY-EXECUTED)
        (asserts! (is-none existing-signature) ERR-NOT-AUTHORIZED)
        
        (map-set guardian-signatures
            { request-id: request-id, guardian: tx-sender }
            { signed: true, timestamp: stacks-block-height }
        )
        
        (let ((current-signatures (get signatures request)))
            (map-set recovery-requests
                { request-id: request-id }
                {
                    family-owner: (get family-owner request),
                    new-owner: (get new-owner request),
                    signatures: (unwrap-panic (as-max-len? (append current-signatures tx-sender) u5)),
                    created-at: (get created-at request),
                    expires-at: (get expires-at request),
                    executed: (get executed request)
                }
            )
        )
        (ok true)
    )
)

(define-public (execute-recovery (request-id uint))
    (let (
        (request (unwrap! (map-get? recovery-requests { request-id: request-id }) ERR-RECOVERY-NOT-FOUND))
        (setup (unwrap! (map-get? family-recovery-setup { family-owner: (get family-owner request) }) ERR-RECOVERY-NOT-FOUND))
    )
        (asserts! (get active setup) ERR-NOT-AUTHORIZED)
        (asserts! (<= stacks-block-height (get expires-at request)) ERR-RECOVERY-EXPIRED)
        (asserts! (not (get executed request)) ERR-ALREADY-EXECUTED)
        (asserts! (>= (len (get signatures request)) (get required-signatures setup)) ERR-INSUFFICIENT-SIGNATURES)
        
        (map-set recovery-requests
            { request-id: request-id }
            {
                family-owner: (get family-owner request),
                new-owner: (get new-owner request),
                signatures: (get signatures request),
                created-at: (get created-at request),
                expires-at: (get expires-at request),
                executed: true
            }
        )
        
        (map-set family-recovery-setup
            { family-owner: (get new-owner request) }
            {
                guardians: (get guardians setup),
                required-signatures: (get required-signatures setup),
                recovery-delay-blocks: (get recovery-delay-blocks setup),
                active: true
            }
        )
        
        (map-delete family-recovery-setup { family-owner: (get family-owner request) })
        (ok (get new-owner request))
    )
)

(define-public (cancel-recovery (request-id uint))
    (let ((request (unwrap! (map-get? recovery-requests { request-id: request-id }) ERR-RECOVERY-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get family-owner request)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get executed request)) ERR-ALREADY-EXECUTED)
        
        (map-set recovery-requests
            { request-id: request-id }
            {
                family-owner: (get family-owner request),
                new-owner: (get new-owner request),
                signatures: (get signatures request),
                created-at: (get created-at request),
                expires-at: u0,
                executed: true
            }
        )
        (ok true)
    )
)

(define-public (update-guardians (new-guardians (list 5 principal)) (new-required-signatures uint))
    (let ((setup (unwrap! (map-get? family-recovery-setup { family-owner: tx-sender }) ERR-RECOVERY-NOT-FOUND)))
        (asserts! (> new-required-signatures u0) ERR-INVALID-GUARDIAN)
        (asserts! (<= new-required-signatures (len new-guardians)) ERR-INVALID-GUARDIAN)
        
        (map-set family-recovery-setup
            { family-owner: tx-sender }
            {
                guardians: new-guardians,
                required-signatures: new-required-signatures,
                recovery-delay-blocks: (get recovery-delay-blocks setup),
                active: true
            }
        )
        (ok true)
    )
)

(define-read-only (get-recovery-setup (family-owner principal))
    (map-get? family-recovery-setup { family-owner: family-owner })
)

(define-read-only (get-recovery-request (request-id uint))
    (map-get? recovery-requests { request-id: request-id })
)

(define-read-only (get-signature-status (request-id uint) (guardian principal))
    (map-get? guardian-signatures { request-id: request-id, guardian: guardian })
)

(define-read-only (count-signatures (request-id uint))
    (let ((request (map-get? recovery-requests { request-id: request-id })))
        (if (is-some request)
            (ok (len (get signatures (unwrap-panic request))))
            ERR-RECOVERY-NOT-FOUND
        )
    )
)
