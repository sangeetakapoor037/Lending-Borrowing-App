(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_LOAN_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u103))
(define-constant ERR_LOAN_HEALTHY (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_LOAN_EXISTS (err u106))
(define-constant ERR_OVERPAYMENT (err u107))
(define-constant ERR_MAX_EXTENSIONS (err u108))

(define-constant COLLATERAL_RATIO u150)
(define-constant LIQUIDATION_THRESHOLD u120)
(define-constant LIQUIDATION_PENALTY u10)
(define-constant ANNUAL_INTEREST_RATE u500)
(define-constant SECONDS_PER_YEAR u31536000)
(define-constant EXTENSION_FEE_RATE u200)
(define-constant MAX_EXTENSIONS u3)

(define-map loans
  { borrower: principal }
  {
    collateral-amount: uint,
    borrowed-amount: uint,
    is-active: bool,
    loan-timestamp: uint,
    extensions-used: uint
  }
)

(define-map pool-balance
  { token: (string-ascii 10) }
  { amount: uint }
)

(define-map user-deposits
  { user: principal }
  { amount: uint }
)

(define-data-var total-pool-balance uint u0)
(define-data-var total-borrowed uint u0)

(define-public (initialize-pool (initial-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> initial-amount u0) ERR_INVALID_AMOUNT)
    (map-set pool-balance { token: "STX" } { amount: initial-amount })
    (var-set total-pool-balance initial-amount)
    (ok true)
  )
)

(define-public (deposit (amount uint))
  (let (
    (current-deposit (default-to { amount: u0 } (map-get? user-deposits { user: tx-sender })))
    (current-pool (var-get total-pool-balance))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set user-deposits 
      { user: tx-sender } 
      { amount: (+ (get amount current-deposit) amount) }
    )
    (var-set total-pool-balance (+ current-pool amount))
    (map-set pool-balance { token: "STX" } { amount: (+ current-pool amount) })
    (ok amount)
  )
)

(define-public (withdraw (amount uint))
  (let (
    (user-balance (default-to { amount: u0 } (map-get? user-deposits { user: tx-sender })))
    (current-pool (var-get total-pool-balance))
    (available-liquidity (- current-pool (var-get total-borrowed)))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get amount user-balance) amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= available-liquidity amount) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-deposits 
      { user: tx-sender } 
      { amount: (- (get amount user-balance) amount) }
    )
    (var-set total-pool-balance (- current-pool amount))
    (map-set pool-balance { token: "STX" } { amount: (- current-pool amount) })
    (ok amount)
  )
)

(define-public (create-loan (collateral-amount uint) (borrow-amount uint))
  (let (
    (existing-loan (map-get? loans { borrower: tx-sender }))
    (required-collateral (/ (* borrow-amount COLLATERAL_RATIO) u100))
    (current-pool (var-get total-pool-balance))
    (current-borrowed (var-get total-borrowed))
    (available-liquidity (- current-pool current-borrowed))
  )
    (asserts! (is-none existing-loan) ERR_LOAN_EXISTS)
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> borrow-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= collateral-amount required-collateral) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (>= available-liquidity borrow-amount) ERR_INSUFFICIENT_BALANCE)
    (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? borrow-amount tx-sender tx-sender)))
    (map-set loans 
      { borrower: tx-sender }
      {
        collateral-amount: collateral-amount,
        borrowed-amount: borrow-amount,
        is-active: true,
        loan-timestamp: stacks-block-height,
        extensions-used: u0
      }
    )
    (var-set total-borrowed (+ current-borrowed borrow-amount))
    (ok { collateral: collateral-amount, borrowed: borrow-amount })
  )
)

(define-public (repay-loan (amount uint))
  (let (
    (loan (unwrap! (map-get? loans { borrower: tx-sender }) ERR_LOAN_NOT_FOUND))
    (borrowed-amount (get borrowed-amount loan))
    (collateral-amount (get collateral-amount loan))
    (loan-timestamp (get loan-timestamp loan))
    (current-borrowed (var-get total-borrowed))
    (blocks-elapsed (- stacks-block-height loan-timestamp))
    (interest-amount (/ (* borrowed-amount ANNUAL_INTEREST_RATE blocks-elapsed) (* u100 u52560)))
    (total-debt (+ borrowed-amount interest-amount))
    (remaining-debt (- total-debt amount))
  )
    (asserts! (get is-active loan) ERR_LOAN_NOT_FOUND)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount total-debt) ERR_OVERPAYMENT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (if (is-eq remaining-debt u0)
      (begin
        (try! (as-contract (stx-transfer? collateral-amount tx-sender tx-sender)))
        (map-delete loans { borrower: tx-sender })
        (var-set total-borrowed (- current-borrowed borrowed-amount))
        (ok { repaid: amount, remaining-debt: u0, collateral-returned: collateral-amount, loan-closed: true })
      )
      (begin
        (map-set loans
          { borrower: tx-sender }
          {
            collateral-amount: collateral-amount,
            borrowed-amount: remaining-debt,
            is-active: true,
            loan-timestamp: stacks-block-height,
            extensions-used: (get extensions-used loan)
          }
        )
        (var-set total-borrowed (- (+ current-borrowed interest-amount) amount))
        (ok { repaid: amount, remaining-debt: remaining-debt, collateral-returned: u0, loan-closed: false })
      )
    )
  )
)

(define-public (liquidate (borrower principal))
  (let (
    (loan (unwrap! (map-get? loans { borrower: borrower }) ERR_LOAN_NOT_FOUND))
    (collateral-amount (get collateral-amount loan))
    (borrowed-amount (get borrowed-amount loan))
    (liquidation-collateral-threshold (/ (* borrowed-amount LIQUIDATION_THRESHOLD) u100))
    (penalty-amount (/ (* collateral-amount LIQUIDATION_PENALTY) u100))
    (liquidator-reward (+ borrowed-amount penalty-amount))
    (remaining-collateral (- collateral-amount liquidator-reward))
    (current-borrowed (var-get total-borrowed))
  )
    (asserts! (get is-active loan) ERR_LOAN_NOT_FOUND)
    (asserts! (< collateral-amount liquidation-collateral-threshold) ERR_LOAN_HEALTHY)
    (try! (stx-transfer? borrowed-amount tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? liquidator-reward tx-sender tx-sender)))
    (if (> remaining-collateral u0)
      (try! (as-contract (stx-transfer? remaining-collateral tx-sender borrower)))
      (try! (as-contract (stx-transfer? u0 tx-sender borrower)))
    )
    (map-delete loans { borrower: borrower })
    (var-set total-borrowed (- current-borrowed borrowed-amount))
    (ok { liquidated: borrowed-amount, reward: liquidator-reward })
  )
)

(define-read-only (get-loan (borrower principal))
  (map-get? loans { borrower: borrower })
)

(define-read-only (get-user-deposit (user principal))
  (map-get? user-deposits { user: user })
)

(define-read-only (get-pool-stats)
  {
    total-pool: (var-get total-pool-balance),
    total-borrowed: (var-get total-borrowed),
    available-liquidity: (- (var-get total-pool-balance) (var-get total-borrowed))
  }
)

(define-read-only (calculate-health-ratio (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (collateral (get collateral-amount loan))
      (borrowed (get borrowed-amount loan))
    )
      (if (> borrowed u0)
        (some (/ (* collateral u100) borrowed))
        none
      )
    )
    none
  )
)

(define-read-only (is-liquidatable (borrower principal))
  (match (calculate-health-ratio borrower)
    health-ratio (< health-ratio LIQUIDATION_THRESHOLD)
    false
  )
)

(define-read-only (get-required-collateral (borrow-amount uint))
  (/ (* borrow-amount COLLATERAL_RATIO) u100)
)

(define-read-only (get-max-borrow (collateral-amount uint))
  (/ (* collateral-amount u100) COLLATERAL_RATIO)
)

(define-read-only (calculate-interest (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (borrowed-amount (get borrowed-amount loan))
      (loan-timestamp (get loan-timestamp loan))
      (blocks-elapsed (- stacks-block-height loan-timestamp))
    )
      (some (/ (* borrowed-amount ANNUAL_INTEREST_RATE blocks-elapsed) (* u100 u52560)))
    )
    none
  )
)

(define-read-only (get-total-debt (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (borrowed-amount (get borrowed-amount loan))
      (loan-timestamp (get loan-timestamp loan))
      (blocks-elapsed (- stacks-block-height loan-timestamp))
      (interest-amount (/ (* borrowed-amount ANNUAL_INTEREST_RATE blocks-elapsed) (* u100 u52560)))
    )
      (some (+ borrowed-amount interest-amount))
    )
    none
  )
)

(define-read-only (get-remaining-debt (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (get borrowed-amount loan)
    u0
  )
)

(define-public (extend-loan)
  (let (
    (loan (unwrap! (map-get? loans { borrower: tx-sender }) ERR_LOAN_NOT_FOUND))
    (borrowed-amount (get borrowed-amount loan))
    (collateral-amount (get collateral-amount loan))
    (loan-timestamp (get loan-timestamp loan))
    (extensions-used (get extensions-used loan))
    (blocks-elapsed (- stacks-block-height loan-timestamp))
    (current-interest (/ (* borrowed-amount ANNUAL_INTEREST_RATE blocks-elapsed) (* u100 u52560)))
    (extension-fee (/ (* borrowed-amount EXTENSION_FEE_RATE) u10000))
    (total-fee-due (+ current-interest extension-fee))
  )
    (asserts! (get is-active loan) ERR_LOAN_NOT_FOUND)
    (asserts! (< extensions-used MAX_EXTENSIONS) ERR_MAX_EXTENSIONS)
    (try! (stx-transfer? total-fee-due tx-sender (as-contract tx-sender)))
    (map-set loans
      { borrower: tx-sender }
      {
        collateral-amount: collateral-amount,
        borrowed-amount: borrowed-amount,
        is-active: true,
        loan-timestamp: stacks-block-height,
        extensions-used: (+ extensions-used u1)
      }
    )
    (ok { 
      extension-fee: extension-fee, 
      interest-paid: current-interest, 
      total-paid: total-fee-due, 
      extensions-remaining: (- MAX_EXTENSIONS (+ extensions-used u1))
    })
  )
)

(define-read-only (calculate-extension-cost (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (borrowed-amount (get borrowed-amount loan))
      (loan-timestamp (get loan-timestamp loan))
      (blocks-elapsed (- stacks-block-height loan-timestamp))
      (current-interest (/ (* borrowed-amount ANNUAL_INTEREST_RATE blocks-elapsed) (* u100 u52560)))
      (extension-fee (/ (* borrowed-amount EXTENSION_FEE_RATE) u10000))
    )
      (some (+ current-interest extension-fee))
    )
    none
  )
)

(define-public (add-collateral (amount uint))
  (let (
    (loan (unwrap! (map-get? loans { borrower: tx-sender }) ERR_LOAN_NOT_FOUND))
    (current-collateral (get collateral-amount loan))
    (borrowed-amount (get borrowed-amount loan))
    (loan-timestamp (get loan-timestamp loan))
    (extensions-used (get extensions-used loan))
    (new-collateral (+ current-collateral amount))
  )
    (asserts! (get is-active loan) ERR_LOAN_NOT_FOUND)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set loans
      { borrower: tx-sender }
      {
        collateral-amount: new-collateral,
        borrowed-amount: borrowed-amount,
        is-active: true,
        loan-timestamp: loan-timestamp,
        extensions-used: extensions-used
      }
    )
    (ok { 
      added: amount, 
      total-collateral: new-collateral,
      new-health-ratio: (/ (* new-collateral u100) borrowed-amount)
    })
  )
)

(define-read-only (calculate-safe-collateral (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (borrowed-amount (get borrowed-amount loan))
      (safe-collateral (/ (* borrowed-amount COLLATERAL_RATIO) u100))
    )
      (some safe-collateral)
    )
    none
  )
)

(define-read-only (get-collateral-shortfall (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan (let (
      (current-collateral (get collateral-amount loan))
      (borrowed-amount (get borrowed-amount loan))
      (safe-collateral (/ (* borrowed-amount COLLATERAL_RATIO) u100))
    )
      (if (< current-collateral safe-collateral)
        (some (- safe-collateral current-collateral))
        (some u0)
      )
    )
    none
  )
)

(define-public (withdraw-collateral (amount uint))
  (let (
    (loan (unwrap! (map-get? loans { borrower: tx-sender }) ERR_LOAN_NOT_FOUND))
    (current-collateral (get collateral-amount loan))
    (borrowed-amount (get borrowed-amount loan))
    (loan-timestamp (get loan-timestamp loan))
    (extensions-used (get extensions-used loan))
    (required-collateral (/ (* borrowed-amount COLLATERAL_RATIO) u100))
    (new-collateral (- current-collateral amount))
  )
    (asserts! (get is-active loan) ERR_LOAN_NOT_FOUND)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-collateral amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= new-collateral required-collateral) ERR_INSUFFICIENT_COLLATERAL)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set loans
      { borrower: tx-sender }
      {
        collateral-amount: new-collateral,
        borrowed-amount: borrowed-amount,
        is-active: true,
        loan-timestamp: loan-timestamp,
        extensions-used: extensions-used
      }
    )
    (ok {
      withdrawn: amount,
      remaining-collateral: new-collateral,
      new-health-ratio: (/ (* new-collateral u100) borrowed-amount)
    })
  )
)
