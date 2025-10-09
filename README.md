# 🏦 DeFi Lending & Borrowing Platform

A decentralized lending and borrowing platform built on Stacks blockchain that demonstrates overcollateralization and liquidation mechanisms.

## 🚀 Features

- 💰 **Deposit STX** to earn from lending pool
- 🏦 **Withdraw STX** from your deposits
- 📈 **Create Loans** with 150% collateralization ratio
- 💸 **Repay Loans** to get collateral back
- ⚡ **Liquidate** unhealthy loans (below 120% health ratio)
- 📊 **Health Monitoring** for all active loans

## 🔧 How It Works

### Overcollateralization
- Borrowers must provide **150%** collateral of the loan amount
- Example: To borrow 100 STX, you need 150 STX as collateral

### Liquidation Mechanism
- Loans become liquidatable when health ratio drops below **120%**
- Liquidators pay the debt and receive collateral + **10% penalty**
- Remaining collateral (if any) is returned to the borrower

## 📋 Usage Instructions

### Initialize Pool (Contract Owner Only)
```clarity
(contract-call? .lending-borrowing-app initialize-pool u1000000)
```

### Deposit STX to Pool
```clarity
(contract-call? .lending-borrowing-app deposit u100000)
```

### Withdraw STX from Pool
```clarity
(contract-call? .lending-borrowing-app withdraw u50000)
```

### Create a Loan
```clarity
;; Borrow 100 STX with 150 STX collateral
(contract-call? .lending-borrowing-app create-loan u150000 u100000)
```

### Repay Loan
```clarity
(contract-call? .lending-borrowing-app repay-loan u100000)
```

### Liquidate Unhealthy Loan
```clarity
(contract-call? .lending-borrowing-app liquidate 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 📊 Read-Only Functions

### Check Loan Status
```clarity
(contract-call? .lending-borrowing-app get-loan 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Check Pool Statistics
```clarity
(contract-call? .lending-borrowing-app get-pool-stats)
```

### Calculate Health Ratio
```clarity
(contract-call? .lending-borrowing-app calculate-health-ratio 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Check if Loan is Liquidatable
```clarity
(contract-call? .lending-borrowing-app is-liquidatable 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 🔢 Key Parameters

- **Collateral Ratio**: 150% (borrowers need 1.5x collateral)
- **Liquidation Threshold**: 120% (loans liquidatable below this ratio)
- **Liquidation Penalty**: 10% (bonus for liquidators)

## ⚠️ Error Codes

- `u100`: Unauthorized access
- `u101`: Insufficient balance
- `u102`: Loan not found
- `u103`: Insufficient collateral
- `u104`: Loan is healthy (cannot liquidate)
- `u105`: Invalid amount
- `u106`: Loan already exists

## 🧪 Testing with Clarinet

```bash
clarinet console
```

Then test the functions in the console environment.

## 🛡️ Security Features

- ✅ Overcollateralization prevents bad debt
- ✅ Liquidation mechanism maintains protocol solvency
- ✅ Owner-only initialization
- ✅ Comprehensive error handling
- ✅ Balance and liquidity checks

## 📈 Example Scenario

1. **Alice deposits** 1000 STX to the lending pool
2. **Bob creates a loan**: deposits 150 STX collateral, borrows 100 STX
3. **STX price drops**: Bob's health ratio falls to 115%
4. **Charlie liquidates**: pays 100 STX debt, receives 150 STX + 15 STX penalty
5. **Protocol remains healthy** with no bad debt

---

Built with ❤️ on Stacks blockchain using Clarity smart contracts
```

## Git Commit Message

```
feat: implement DeFi lending platform with overcollateralization and liquidation
```

## GitHub Pull Request Title

```
🏦 Add DeFi Lending & Borrowing Platform MVP
```

## GitHub Pull Request Description

```markdown
## 🚀 What's Added

This PR introduces a complete DeFi lending and borrowing platform MVP that demonstrates key DeFi concepts:

### ✨ Core Features
- **Lending Pool**: Users can deposit/withdraw STX to earn from borrowing fees
- **Overcollateralized Loans**: 150% collateralization ratio ensures protocol safety
- **Liquidation System**: Automated liquidation when health ratio drops below 120%
- **Health Monitoring**: Real-time loan health calculation and monitoring

### 🔧 Smart Contract Functions
- `initialize-pool` - Set up initial lending pool (owner only)
- `deposit/withdraw` - Manage user deposits in lending pool
- `create-loan` - Create overcollateralized loans
- `repay-loan` - Repay loans and retrieve collateral
- `liquidate` - Liquidate unhealthy loans with penalty rewards

### 📊 Read-Only Functions
- Pool statistics and available liquidity
- Loan status and health ratio calculations
- Liquidation eligibility checks
- User deposit tracking

### 🛡️ Security & Risk Management
- Comprehensive error handling with descriptive error codes
- Overcollateralization prevents protocol insolvency
- Liquidation mechanism with 10% penalty incentivizes liquidators
- Balance and liquidity validation on all operations

### 📚 Educational Value
Perfect for learning DeFi concepts including:
- How overcollateralization works in practice
- Liquidation mechanics and incentives
- Pool-based lending protocols
- Risk management in DeFi

Ready for testing and deployment on Stacks testnet! 🎉

