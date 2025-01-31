;; DigitalPass: Smart Membership System
;; Description: Smart contract for managing tiered digital memberships with automatic renewal and preview periods

;; Constants
(define-constant admin-address tx-sender)
(define-constant err-admin-only (err u100))
(define-constant err-setup-complete (err u101))
(define-constant err-not-setup (err u102))
(define-constant err-membership-expired (err u103))
(define-constant err-invalid-plan (err u104))
(define-constant err-not-permitted (err u105))
(define-constant err-renewal-failed (err u106))
(define-constant err-preview-used (err u107))
(define-constant err-invalid-member (err u108))
(define-constant err-invalid-block-time (err u109))

;; Data Variables
(define-data-var system-initialized bool false)

;; Data Maps
(define-map memberships
    principal
    {plan: (string-ascii 6),
     end-date: uint,
     status: bool,
     auto-renewal: bool,
     preview-claimed: bool,
     preview-end: uint})

(define-map membership-plans
    (string-ascii 6)
    {cost: uint,
     period: uint,
     preview-period: uint,
     features: (string-ascii 50)})

;; Private Functions
(define-private (is-admin)
    (is-eq tx-sender admin-address))

(define-private (is-valid-plan (plan (string-ascii 6)))
    (is-some (map-get? membership-plans plan)))

(define-private (is-valid-member (member principal))
    (and 
        (not (is-eq member admin-address))
        (not (is-eq member tx-sender))))

(define-private (is-membership-active (member principal))
    (begin 
        (asserts! (is-valid-member member) false)
        (let ((membership (unwrap! (map-get? memberships member) false)))
            (and 
                (get status membership)
                (> (get end-date membership) block-height)))))

(define-private (process-auto-renewal (member principal))
    (begin 
        (asserts! (is-valid-member member) (err err-invalid-member))
        (let ((current-membership (unwrap! (map-get? memberships member) (err err-renewal-failed)))
              (plan-details (unwrap! (map-get? membership-plans (get plan current-membership)) (err err-invalid-plan))))
            
            (if (get auto-renewal current-membership)
                (begin
                    (asserts! (> (get period plan-details) u0) (err err-invalid-plan))
                    (map-set memberships member
                        {plan: (get plan current-membership),
                         end-date: (+ block-height (get period plan-details)),
                         status: true,
                         auto-renewal: true,
                         preview-claimed: (get preview-claimed current-membership),
                         preview-end: (get preview-end current-membership)})
                    (ok true))
                (err err-renewal-failed)))))

;; Public Functions
(define-public (setup)
    (begin
        (asserts! (is-admin) err-admin-only)
        (asserts! (not (var-get system-initialized)) err-setup-complete)
        
        ;; Initialize membership plans with preview periods
        (map-set membership-plans "basic"
            {cost: u100,
             period: u4320,
             preview-period: u288,
             features: "Standard digital access"})
        
        (map-set membership-plans "plus"
            {cost: u250,
             period: u4320,
             preview-period: u288,
             features: "Enhanced access + bonus content"})
        
        (map-set membership-plans "pro"
            {cost: u500,
             period: u4320,
             preview-period: u288,
             features: "Complete access + priority features"})
        
        (var-set system-initialized true)
        (ok true)))

(define-public (join (plan (string-ascii 6)) (enable-renewal (optional bool)))
    (begin 
        (asserts! (is-valid-plan plan) err-invalid-plan)
        
        (let ((plan-details (unwrap! (map-get? membership-plans plan) err-invalid-plan))
              (cost (get cost plan-details))
              (period (get period plan-details))
              (preview-period (get preview-period plan-details))
              (current-membership (map-get? memberships tx-sender)))
            
            (asserts! 
                (or 
                    (is-none current-membership) 
                    (not (get preview-claimed (unwrap-panic current-membership))))
                err-preview-used)
            
            (asserts! (> period u0) err-invalid-plan)
            (asserts! (> preview-period u0) err-invalid-plan)
            
            (map-set memberships tx-sender
                {plan: plan,
                 end-date: (+ block-height 
                             (if (is-none current-membership) 
                                 preview-period 
                                 period)),
                 status: true,
                 auto-renewal: (default-to false enable-renewal),
                 preview-claimed: (is-none current-membership),
                 preview-end: (+ block-height preview-period)})
            
            (ok true))))

(define-public (extend-membership)
    (let ((current-membership (unwrap! (map-get? memberships tx-sender) err-not-permitted))
          (plan-details (unwrap! (map-get? membership-plans (get plan current-membership)) err-invalid-plan)))
        
        (map-set memberships tx-sender
            {plan: (get plan current-membership),
             end-date: (+ block-height (get period plan-details)),
             status: true,
             auto-renewal: (get auto-renewal current-membership),
             preview-claimed: (get preview-claimed current-membership),
             preview-end: (get preview-end current-membership)})
        
        (ok true)))

(define-public (end-membership)
    (let ((current-membership (unwrap! (map-get? memberships tx-sender) err-not-permitted)))
        (map-set memberships tx-sender
            {plan: (get plan current-membership),
             end-date: block-height,
             status: false,
             auto-renewal: false,
             preview-claimed: (get preview-claimed current-membership),
             preview-end: (get preview-end current-membership)})
        
        (ok true)))

(define-public (set-auto-renewal (enable bool))
    (let ((current-membership (unwrap! (map-get? memberships tx-sender) err-not-permitted)))
        (map-set memberships tx-sender
            {plan: (get plan current-membership),
             end-date: (get end-date current-membership),
             status: (get status current-membership),
             auto-renewal: enable,
             preview-claimed: (get preview-claimed current-membership),
             preview-end: (get preview-end current-membership)})
        
        (ok true)))

(define-public (run-renewals (members (list 100 principal)))
    (begin
        (asserts! (is-admin) err-admin-only)
        (let ((renewal-results (map process-auto-renewal members)))
            (ok true))))

(define-public (verify-membership (member principal))
    (begin
        (asserts! (is-valid-member member) (err err-invalid-member))
        (ok (is-membership-active member))))

(define-read-only (get-membership-details (member principal))
    (map-get? memberships member))

(define-read-only (get-plan-details (plan (string-ascii 6)))
    (map-get? membership-plans plan))

;; Contract initialization check
(asserts! (is-admin) err-not-permitted)