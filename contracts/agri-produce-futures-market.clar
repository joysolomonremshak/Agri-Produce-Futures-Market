(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_CONTRACT_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_SETTLED (err u102))
(define-constant ERR_INSUFFICIENT_DEPOSIT (err u103))
(define-constant ERR_CONTRACT_EXPIRED (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_ALREADY_EXISTS (err u106))
(define-constant ERR_INVALID_QUANTITY (err u107))
(define-constant ERR_INVALID_PRICE (err u108))
(define-constant ERR_NO_PENDING_AMENDMENT (err u109))
(define-constant ERR_AMENDMENT_PENDING (err u110))
(define-constant ERR_DISPUTE_EXISTS (err u111))
(define-constant ERR_NO_DISPUTE (err u112))
(define-constant ERR_DISPUTE_RESOLVED (err u113))
(define-constant ERR_NOT_ARBITER (err u114))

(define-data-var next-contract-id uint u1)
(define-data-var arbiter-address principal CONTRACT_OWNER)

(define-map contracts
  uint
  {
    farmer: principal,
    buyer: principal,
    produce-type: (string-ascii 50),
    quantity: uint,
    price-per-unit: uint,
    farmer-deposit: uint,
    buyer-deposit: uint,
    delivery-date: uint,
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map contract-deposits
  uint
  {
    farmer-deposited: uint,
    buyer-deposited: uint,
    total-locked: uint
  }
)

(define-map contract-amendments
  uint
  {
    proposed-by: principal,
    quantity: (optional uint),
    price-per-unit: (optional uint),
    delivery-date: (optional uint),
    farmer-deposit: (optional uint),
    buyer-deposit: (optional uint),
    proposed-at: uint,
    status: (string-ascii 20)
  }
)

(define-map contract-disputes
  uint
  {
    raised-by: principal,
    reason: (string-ascii 200),
    farmer-claim: uint,
    buyer-claim: uint,
    raised-at: uint,
    resolved: bool,
    resolution: (optional (string-ascii 200)),
    farmer-payout: (optional uint),
    buyer-payout: (optional uint)
  }
)

(define-public (create-futures-contract 
  (buyer principal)
  (produce-type (string-ascii 50))
  (quantity uint)
  (price-per-unit uint)
  (delivery-date uint)
  (farmer-deposit uint)
  (buyer-deposit uint))
  (let
    (
      (contract-id (var-get next-contract-id))
      (total-value (* quantity price-per-unit))
    )
    (asserts! (> quantity u0) ERR_INVALID_QUANTITY)
    (asserts! (> price-per-unit u0) ERR_INVALID_PRICE)
    (asserts! (> delivery-date stacks-block-height) ERR_CONTRACT_EXPIRED)
    (asserts! (>= farmer-deposit (/ total-value u10)) ERR_INSUFFICIENT_DEPOSIT)
    (asserts! (>= buyer-deposit (/ total-value u10)) ERR_INSUFFICIENT_DEPOSIT)
    
    (map-set contracts contract-id
      {
        farmer: tx-sender,
        buyer: buyer,
        produce-type: produce-type,
        quantity: quantity,
        price-per-unit: price-per-unit,
        farmer-deposit: farmer-deposit,
        buyer-deposit: buyer-deposit,
        delivery-date: delivery-date,
        created-at: stacks-block-height,
        status: "OPEN"
      }
    )
    
    (map-set contract-deposits contract-id
      {
        farmer-deposited: u0,
        buyer-deposited: u0,
        total-locked: u0
      }
    )
    
    (var-set next-contract-id (+ contract-id u1))
    (ok contract-id)
  )
)

(define-public (deposit-farmer (contract-id uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
      (required-deposit (get farmer-deposit contract-data))
    )
    (asserts! (is-eq tx-sender (get farmer contract-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status contract-data) "OPEN") ERR_INVALID_STATUS)
    (asserts! (is-eq (get farmer-deposited deposit-data) u0) ERR_ALREADY_EXISTS)
    (asserts! (is-none (map-get? contract-amendments contract-id)) ERR_AMENDMENT_PENDING)
    
    (try! (stx-transfer? required-deposit tx-sender (as-contract tx-sender)))
    
    (map-set contract-deposits contract-id
      {
        farmer-deposited: required-deposit,
        buyer-deposited: (get buyer-deposited deposit-data),
        total-locked: (+ (get total-locked deposit-data) required-deposit)
      }
    )
    
    (let ((updated-deposits (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND)))
      (if (and 
            (> (get farmer-deposited updated-deposits) u0)
            (> (get buyer-deposited updated-deposits) u0))
        (begin
          (map-set contracts contract-id
            (merge contract-data { status: "ACTIVE" }))
          (ok "CONTRACT_ACTIVE"))
        (ok "FARMER_DEPOSITED"))
    )
  )
)

(define-public (deposit-buyer (contract-id uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
      (required-deposit (get buyer-deposit contract-data))
    )
    (asserts! (is-eq tx-sender (get buyer contract-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status contract-data) "OPEN") ERR_INVALID_STATUS)
    (asserts! (is-eq (get buyer-deposited deposit-data) u0) ERR_ALREADY_EXISTS)
    (asserts! (is-none (map-get? contract-amendments contract-id)) ERR_AMENDMENT_PENDING)
    
    (try! (stx-transfer? required-deposit tx-sender (as-contract tx-sender)))
    
    (map-set contract-deposits contract-id
      {
        farmer-deposited: (get farmer-deposited deposit-data),
        buyer-deposited: required-deposit,
        total-locked: (+ (get total-locked deposit-data) required-deposit)
      }
    )
    
    (let ((updated-deposits (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND)))
      (if (and 
            (> (get farmer-deposited updated-deposits) u0)
            (> (get buyer-deposited updated-deposits) u0))
        (begin
          (map-set contracts contract-id
            (merge contract-data { status: "ACTIVE" }))
          (ok "CONTRACT_ACTIVE"))
        (ok "BUYER_DEPOSITED"))
    )
  )
)

(define-public (settle-delivery (contract-id uint) (delivered-quantity uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
      (total-contract-value (* (get quantity contract-data) (get price-per-unit contract-data)))
      (delivered-value (* delivered-quantity (get price-per-unit contract-data)))
      (farmer-payout (+ (get farmer-deposited deposit-data) delivered-value))
      (buyer-refund (- (get total-locked deposit-data) farmer-payout))
    )
    (asserts! (is-eq tx-sender (get farmer contract-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status contract-data) "ACTIVE") ERR_INVALID_STATUS)
    (asserts! (<= delivered-quantity (get quantity contract-data)) ERR_INVALID_QUANTITY)
    
    (as-contract (try! (stx-transfer? farmer-payout tx-sender (get farmer contract-data))))
    (as-contract (try! (stx-transfer? buyer-refund tx-sender (get buyer contract-data))))
    
    (map-set contracts contract-id
      (merge contract-data { status: "SETTLED" }))
    
    (map-delete contract-deposits contract-id)
    (ok delivered-quantity)
  )
)

(define-public (cancel-contract (contract-id uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
    )
    (asserts! (or 
                (is-eq tx-sender (get farmer contract-data))
                (is-eq tx-sender (get buyer contract-data))) ERR_NOT_AUTHORIZED)
    (asserts! (or 
                (is-eq (get status contract-data) "OPEN")
                (> stacks-block-height (get delivery-date contract-data))) ERR_INVALID_STATUS)
    
    (if (> (get farmer-deposited deposit-data) u0)
      (as-contract (try! (stx-transfer? (get farmer-deposited deposit-data) tx-sender (get farmer contract-data))))
      true)
    
    (if (> (get buyer-deposited deposit-data) u0)
      (as-contract (try! (stx-transfer? (get buyer-deposited deposit-data) tx-sender (get buyer contract-data))))
      true)
    
    (map-set contracts contract-id
      (merge contract-data { status: "CANCELLED" }))
    
    (map-delete contract-deposits contract-id)
    (ok "CONTRACT_CANCELLED")
  )
)

(define-public (propose-amendment 
  (contract-id uint)
  (new-quantity (optional uint))
  (new-price-per-unit (optional uint))
  (new-delivery-date (optional uint))
  (new-farmer-deposit (optional uint))
  (new-buyer-deposit (optional uint)))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
    )
    (asserts! (or 
                (is-eq tx-sender (get farmer contract-data))
                (is-eq tx-sender (get buyer contract-data))) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status contract-data) "OPEN") ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? contract-amendments contract-id)) ERR_AMENDMENT_PENDING)
    
    (if (is-some new-quantity)
      (asserts! (> (unwrap-panic new-quantity) u0) ERR_INVALID_QUANTITY)
      true)
    (if (is-some new-price-per-unit)
      (asserts! (> (unwrap-panic new-price-per-unit) u0) ERR_INVALID_PRICE)
      true)
    (if (is-some new-delivery-date)
      (asserts! (> (unwrap-panic new-delivery-date) stacks-block-height) ERR_CONTRACT_EXPIRED)
      true)
    
    (map-set contract-amendments contract-id
      {
        proposed-by: tx-sender,
        quantity: new-quantity,
        price-per-unit: new-price-per-unit,
        delivery-date: new-delivery-date,
        farmer-deposit: new-farmer-deposit,
        buyer-deposit: new-buyer-deposit,
        proposed-at: stacks-block-height,
        status: "PENDING"
      }
    )
    (ok "AMENDMENT_PROPOSED")
  )
)

(define-public (accept-amendment (contract-id uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (amendment-data (unwrap! (map-get? contract-amendments contract-id) ERR_NO_PENDING_AMENDMENT))
    )
    (asserts! (or 
                (is-eq tx-sender (get farmer contract-data))
                (is-eq tx-sender (get buyer contract-data))) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq tx-sender (get proposed-by amendment-data))) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status amendment-data) "PENDING") ERR_INVALID_STATUS)
    
    (let
      (
        (updated-quantity (default-to (get quantity contract-data) (get quantity amendment-data)))
        (updated-price (default-to (get price-per-unit contract-data) (get price-per-unit amendment-data)))
        (updated-delivery (default-to (get delivery-date contract-data) (get delivery-date amendment-data)))
        (updated-farmer-deposit (default-to (get farmer-deposit contract-data) (get farmer-deposit amendment-data)))
        (updated-buyer-deposit (default-to (get buyer-deposit contract-data) (get buyer-deposit amendment-data)))
        (total-value (* updated-quantity updated-price))
      )
      (asserts! (>= updated-farmer-deposit (/ total-value u10)) ERR_INSUFFICIENT_DEPOSIT)
      (asserts! (>= updated-buyer-deposit (/ total-value u10)) ERR_INSUFFICIENT_DEPOSIT)
      
      (map-set contracts contract-id
        (merge contract-data {
          quantity: updated-quantity,
          price-per-unit: updated-price,
          delivery-date: updated-delivery,
          farmer-deposit: updated-farmer-deposit,
          buyer-deposit: updated-buyer-deposit
        })
      )
      
      (map-delete contract-amendments contract-id)
      (ok "AMENDMENT_ACCEPTED")
    )
  )
)

(define-public (reject-amendment (contract-id uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (amendment-data (unwrap! (map-get? contract-amendments contract-id) ERR_NO_PENDING_AMENDMENT))
    )
    (asserts! (or 
                (is-eq tx-sender (get farmer contract-data))
                (is-eq tx-sender (get buyer contract-data))) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq tx-sender (get proposed-by amendment-data))) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status amendment-data) "PENDING") ERR_INVALID_STATUS)
    
    (map-delete contract-amendments contract-id)
    (ok "AMENDMENT_REJECTED")
  )
)

(define-read-only (get-contract (contract-id uint))
  (map-get? contracts contract-id)
)

(define-read-only (get-contract-deposits (contract-id uint))
  (map-get? contract-deposits contract-id)
)

(define-read-only (get-next-contract-id)
  (var-get next-contract-id)
)

(define-read-only (calculate-contract-value (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data (* (get quantity contract-data) (get price-per-unit contract-data))
    u0
  )
)

(define-read-only (is-contract-expired (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data (> stacks-block-height (get delivery-date contract-data))
    true
  )
)

(define-read-only (get-contract-status (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data (get status contract-data)
    "NOT_FOUND"
  )
)

(define-read-only (get-contract-amendment (contract-id uint))
  (map-get? contract-amendments contract-id)
)

(define-public (set-arbiter (new-arbiter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set arbiter-address new-arbiter)
    (ok new-arbiter)
  )
)

(define-public (raise-dispute 
  (contract-id uint)
  (reason (string-ascii 200))
  (claimed-quantity uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
      (is-farmer (is-eq tx-sender (get farmer contract-data)))
      (is-buyer (is-eq tx-sender (get buyer contract-data)))
      (farmer-claim (if is-farmer claimed-quantity u0))
      (buyer-claim (if is-buyer claimed-quantity u0))
    )
    (asserts! (or is-farmer is-buyer) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status contract-data) "ACTIVE") ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? contract-disputes contract-id)) ERR_DISPUTE_EXISTS)
    (asserts! (<= claimed-quantity (get quantity contract-data)) ERR_INVALID_QUANTITY)
    
    (map-set contract-disputes contract-id
      {
        raised-by: tx-sender,
        reason: reason,
        farmer-claim: farmer-claim,
        buyer-claim: buyer-claim,
        raised-at: stacks-block-height,
        resolved: false,
        resolution: none,
        farmer-payout: none,
        buyer-payout: none
      }
    )
    
    (map-set contracts contract-id
      (merge contract-data { status: "DISPUTED" }))
    
    (ok "DISPUTE_RAISED")
  )
)

(define-public (submit-counter-claim 
  (contract-id uint)
  (counter-quantity uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (dispute-data (unwrap! (map-get? contract-disputes contract-id) ERR_NO_DISPUTE))
      (is-farmer (is-eq tx-sender (get farmer contract-data)))
      (is-buyer (is-eq tx-sender (get buyer contract-data)))
    )
    (asserts! (or is-farmer is-buyer) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq tx-sender (get raised-by dispute-data))) ERR_NOT_AUTHORIZED)
    (asserts! (not (get resolved dispute-data)) ERR_DISPUTE_RESOLVED)
    (asserts! (<= counter-quantity (get quantity contract-data)) ERR_INVALID_QUANTITY)
    
    (let
      (
        (updated-farmer-claim (if is-farmer counter-quantity (get farmer-claim dispute-data)))
        (updated-buyer-claim (if is-buyer counter-quantity (get buyer-claim dispute-data)))
      )
      (map-set contract-disputes contract-id
        (merge dispute-data {
          farmer-claim: updated-farmer-claim,
          buyer-claim: updated-buyer-claim
        })
      )
      (ok "COUNTER_CLAIM_SUBMITTED")
    )
  )
)

(define-public (resolve-dispute 
  (contract-id uint)
  (resolution (string-ascii 200))
  (awarded-quantity uint))
  (let
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR_CONTRACT_NOT_FOUND))
      (dispute-data (unwrap! (map-get? contract-disputes contract-id) ERR_NO_DISPUTE))
      (deposit-data (unwrap! (map-get? contract-deposits contract-id) ERR_CONTRACT_NOT_FOUND))
      (delivered-value (* awarded-quantity (get price-per-unit contract-data)))
      (farmer-payout (+ (get farmer-deposited deposit-data) delivered-value))
      (buyer-refund (- (get total-locked deposit-data) farmer-payout))
    )
    (asserts! (is-eq tx-sender (var-get arbiter-address)) ERR_NOT_ARBITER)
    (asserts! (is-eq (get status contract-data) "DISPUTED") ERR_INVALID_STATUS)
    (asserts! (not (get resolved dispute-data)) ERR_DISPUTE_RESOLVED)
    (asserts! (<= awarded-quantity (get quantity contract-data)) ERR_INVALID_QUANTITY)
    
    (as-contract (try! (stx-transfer? farmer-payout tx-sender (get farmer contract-data))))
    (as-contract (try! (stx-transfer? buyer-refund tx-sender (get buyer contract-data))))
    
    (map-set contract-disputes contract-id
      (merge dispute-data {
        resolved: true,
        resolution: (some resolution),
        farmer-payout: (some farmer-payout),
        buyer-payout: (some buyer-refund)
      })
    )
    
    (map-set contracts contract-id
      (merge contract-data { status: "RESOLVED" }))
    
    (map-delete contract-deposits contract-id)
    (ok awarded-quantity)
  )
)

(define-read-only (get-dispute (contract-id uint))
  (map-get? contract-disputes contract-id)
)

(define-read-only (get-arbiter)
  (var-get arbiter-address)
)
