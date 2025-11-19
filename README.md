# 🏦 Lending & Borrowing Protocol

A decentralized Lending & Borrowing Protocol that enables users to deposit assets as collateral, borrow tokens, repay loans, and be liquidated if their position becomes unhealthy. The protocol supports multiple markets, each with its own collateral factor, supply rate, and borrow rate. Built with Solidity and Foundry, with a complete testing suite.

### 🤔 What is Lending Protocol on DeFi?

A lending protocol is a decentralized system that allows users to **lend** their tokens to earn interest or **borrow** tokens by providing collateral. Instead of relying on a bank, users interact directly with smart contracts, which autonomously manage deposits, loans, interest rates, and liquidations.

**How the flow works:**

- **Lending**: Users deposit tokens into the protocol, adding liquidity to the pool. In return, they earn interest over time.
- **Borrowing**: Users lock collateral (also deposited tokens) and borrow against it. The amount they can borrow depends on the asset’s collateral factor, which defines how much of the collateral’s value counts as borrowing power.
- **Position health**: Each borrower has a collateralization ratio. If this ratio falls below the liquidation threshold, the position becomes “unhealthy.”
- **Liquidation**: When a position is unhealthy, anyone can act as a liquidator—repaying part of the borrower’s debt in exchange for a portion of their collateral. This mechanism ensures the protocol remains solvent at all times.

By replacing intermediaries with transparent smart contracts, lending protocols enable permissionless, trustless lending and borrowing, controlled entirely by code and accessible to anyone.

## ✨ Features

- 🏛️ **Multi-Market System**: Independent markets for each supported token with customizable collateral factor, supply rate, and borrow rate.
- 💰 **Token Deposits**: Users can deposit tokens into any active market using deposit().
- 💸 **Secure Withdrawals**: Withdrawals are protected by collateral checks via canWithdraw().
- 🧮 **Borrowing Logic**: Borrowing power is validated using real collateral ratios through canBorrow().
- 📉 **Collateralization Ratio Tracking**: Each user’s health is determined via getCollateralizationRatio().
- ⚠️ **Liquidation Mechanism**: Unhealthy positions can be liquidated using liquidate(), rewarding the liquidator.
- 🛠️ **Best Collateral Selection**: Automatic collateral selection for liquidation using findBestCollateral().
- 🔐 **Reentrancy Protection**: Critical functions protected using OpenZeppelin’s ReentrancyGuard.
- 🪙 **Safe Token Transfers**: All ERC20 operations use SafeERC20 for compatibility and safety.
- 🏁 **Pausable Emergency Halt**: Owner can pause and unpause the protocol through pause() and unpause().
- 🧪 **Full Testing Suite**: All core functions include tests: happy paths, reverts, edge cases, and artificial liquidations using vm.store().
- 🧩 **Getter Utilities**: View functions such as getUser(), getMarket(), getUserDeposit(), and getUserBorrow() for frontend integration.

## 🧩 Smart Contract Architecture & Security Patterns

### Design and Architecture Patterns

- **Multi-market modularity**: Each token market maintains independent parameters and state.
- **Modular Separate Concerns**: User balances, borrow tracking, and market configuration are cleanly isolated.
- **CEI Pattern**: All external functions follow the Checks-Effects-Interactions pattern to minimize vulnerabilities.
- **Gas-efficient mappings**: Direct mapping access for deposits and borrows.vulnerabilities.

### Security Measures

- **🔑 Access Restriction**: `onlyOwner` modifier restricts access to important functions like `addMarket` for critical vulnerabilities and prevention attacks.
- 🪙 **SafeERC20**: All token transfers use `SafeERC20` to handle non-standard ERC20 implementations safely.
- 🛡️ **Reentrancy Protection**: Critical functions (`deposit`, `withdraw`, `borrow`, `liquidate`) are protected with OpenZeppelin's `ReentrancyGuard`.
- 📢 **Event Logging**: All state mutations emit events for transparency and off-chain monitoring, such as `MarketAdded`, `Deposit`, `Withdraw`, `Liquidate`, and more.
- 🧪 **Testing**: Complete testing suite with +85% coverage.

## 🧪 Tests

Complete testing suite using **Foundry**, achieving +85% code coverage across all contracts.
The suite includes happy paths, negative paths, and edge cases to ensure robustness.

### Coverage Results:

```bash
Ran 1 test suite in 279.56ms (8.23ms CPU time): 51 tests passed, 0 failed, 0 skipped (51 total tests)

╭-------------------------+------------------+------------------+----------------+-----------------╮
| File                    | % Lines          | % Statements     | % Branches     | % Funcs         |
+==================================================================================================+
| src/LendingProtocol.sol | 93.75% (165/176) | 92.74% (166/179) | 85.29% (58/68) | 100.00% (23/23) |
|-------------------------+------------------+------------------+----------------+-----------------|
| src/MockToken.sol       | 100.00% (9/9)    | 100.00% (5/5)    | 100.00% (0/0)  | 100.00% (4/4)   |
|-------------------------+------------------+------------------+----------------+-----------------|
| Total                   | 94.05% (174/185) | 92.93% (171/184) | 85.29% (58/68) | 100.00% (27/27) |
╰-------------------------+------------------+------------------+----------------+-----------------╯

# Run all tests
forge test

# Run specific test
forge test -vvvv --match-test test_withdraw_revertIfInactiveMarket

# Check coverage
forge coverage
```

## 🧠 Technologies Used

- ⚙️ **Solidity** (`^0.8.24`) – smart contract programming language
- 🧪 **Foundry** – framework for development, testing, fuzzing, invariants and deployment
- 📚 **OpenZeppelin Contracts** – `ERC20`, `Ownable`, `ReentrancyGuard`, `SafeERC20`, `Pausable`
- 🛠️ **MockToken** – custom ERC20 token implementation for testing
- 🔬 **Cheatcodes** – `vm.startPrank`, `vm.expectRevert`, `vm.expectEmit`

## 📜 License

This project is licensed under the MIT License.
