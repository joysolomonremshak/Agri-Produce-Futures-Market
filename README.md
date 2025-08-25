# 🌾 Agri-Produce Futures Market

A blockchain-powered smart contract platform that enables farmers and buyers to lock in crop prices before harvest, providing price certainty and risk management for agricultural trades.

## 🎯 Overview

The Agri-Produce Futures Market allows:
- 👨‍🌾 **Farmers** to secure guaranteed prices for their crops before harvest
- 🏪 **Buyers** to lock in supply and pricing for future agricultural produce
- 💰 **Both parties** to deposit collateral ensuring contract commitment
- ⚖️ **Automated settlement** based on actual delivery quantities

## ✨ Key Features

- 📝 **Create Futures Contracts**: Define produce type, quantity, price, and delivery terms
- 🔒 **Deposit System**: Both parties provide collateral (minimum 10% of contract value)
- 🚚 **Flexible Settlement**: Settle based on actual delivered quantities
- ❌ **Cancellation Protection**: Cancel contracts before activation or after expiry
- 📊 **Transparent Tracking**: View contract status and deposit information

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://docs.stacks.co/docs/clarity/clarinet) installed
- Stacks wallet with STX tokens

### Installation

1. Clone the repository:
```bash
git clone https://github.com/joysolomonremshak/Agri-Produce-Futures-Market.git
cd Agri-Produce-Futures-Market
```

2. Install dependencies:
```bash
clarinet requirements
```

3. Run tests:
```bash
clarinet test
```

## 📋 Usage Guide

### 1. Creating a Futures Contract

**Farmer** creates a new futures contract:

```clarity
(contract-call? .agri-produce-futures-market create-futures-contract
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 ;; buyer address
  "corn"                                          ;; produce type
  u1000                                          ;; quantity (1000 units)
  u50                                            ;; price per unit (50 STX)
  u144000                                        ;; delivery date (block height)
  u5000                                          ;; farmer deposit (5000 microSTX)
  u5000                                          ;; buyer deposit (5000 microSTX)
)
```

### 2. Making Deposits

**Farmer** deposits collateral:
```clarity
(contract-call? .agri-produce-futures-market deposit-farmer u1)
```

**Buyer** deposits collateral:
```clarity
(contract-call? .agri-produce-futures-market deposit-buyer u1)
```

### 3. Settling Delivery

**Farmer** settles the contract after delivery:
```clarity
(contract-call? .agri-produce-futures-market settle-delivery u1 u950) ;; delivered 950 units
```

### 4. Contract Cancellation

Either party can cancel before both deposits are made:
```clarity
(contract-call? .agri-produce-futures-market cancel-contract u1)
```

## 🔍 Contract Status Flow

1. **OPEN** → Contract created, waiting for deposits
2. **ACTIVE** → Both parties deposited, contract is live
3. **SETTLED** → Delivery completed and payments distributed
4. **CANCELLED** → Contract cancelled, deposits refunded

## 📖 Read-Only Functions

- `get-contract(contract-id)` - View contract details
- `get-contract-deposits(contract-id)` - View deposit information
- `calculate-contract-value(contract-id)` - Get total contract value
- `is-contract-expired(contract-id)` - Check if contract is expired
- `get-contract-status(contract-id)` - Get current contract status

## 🔐 Security Features

- ✅ Minimum deposit requirements (10% of contract value)
- ✅ Authorization checks for all operations
- ✅ Contract expiry protection
- ✅ Status validation for state transitions
- ✅ Deposit locking mechanism

## 🎮 Example Scenario

1. **Bob (Farmer)** expects to harvest 1000 units of corn in 3 months
2. **Alice (Buyer)** needs corn and wants to lock in the price at 50 STX per unit
3. **Bob** creates a futures contract with Alice as the buyer
4. Both deposit 5000 microSTX (10% of 50,000 microSTX total value)
5. At harvest time, **Bob** delivers 950 units and settles the contract
6. **Bob** receives: 5000 (his deposit) + 47,500 (950 × 50) = 52,500 microSTX
7. **Alice** receives: 2,500 microSTX refund for the undelivered 50 units

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Check contract deployment:
```bash
clarinet console
```

## 📞 Support

For questions and support, please open an issue on GitHub.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
