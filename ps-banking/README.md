# ps-banking (Enhanced Version)
Compatible with QBCore and ESX with enhanced security, validation, and features.

## 🚀 New Features

### Security Enhancements
- ✅ Daily transfer limits
- ✅ Transaction amount validation
- ✅ Comprehensive audit logging
- ✅ Account status management (active, frozen, closed)
- ✅ Rate limiting and fraud prevention

### Database Improvements
- ✅ Indexed for better performance
- ✅ Constraints for data integrity
- ✅ Automatic timestamps
- ✅ Audit log table
- ✅ Transfer limits tracking

### Configuration
- ✅ Extensive security settings
- ✅ Configurable transaction fees
- ✅ Account limits and rules
- ✅ Discord webhook integration
- ✅ Notification settings

### New Exports
- ✅ Account management functions
- ✅ Balance checking utilities
- ✅ Transaction queries
- ✅ Bill management
- ✅ Inter-account transfers

See [CHANGELOG.md](CHANGELOG.md) for complete list of improvements.

# Dependencies
1. [qb-core](https://github.com/qbcore-framework/qb-core) or [ESX](https://github.com/esx-framework)
2. [ox_lib](https://github.com/overextended/ox_lib) (3.20.0+)
3. [oxmysql](https://github.com/overextended/oxmysql)

# Installation
* Download release files.
* Drag and drop resource into your server files.
* Start resource through server.cfg.
* **IMPORTANT**: Backup your database before running the SQL file.
* Add the ps-banking.sql file to your database.
* Configure config.lua according to your server needs.
* Restart your server.

## Exports

### Create Bill (Enhanced)
```lua
-- Creates a bill invoice in the bank with optional due date
exports["ps-banking"]:createBill({
    identifier = "HVZ84591", -- citizen id (who receives the bill)
    identifier2 = "ABC12345", -- optional: who created the bill
    description = "Utility Bill",
    type = "Expense",
    amount = 150.00,
    dueDays = 7 -- optional: days until due (default: 7)
})
```

### Account Management
```lua
-- Get all accounts for a player
local accounts = exports["ps-banking"]:GetPlayerAllAccounts(identifier)

-- Freeze an account
exports["ps-banking"]:FreezeAccount(accountId)

-- Unfreeze an account
exports["ps-banking"]:UnfreezeAccount(accountId)

-- Close an account
exports["ps-banking"]:CloseAccount(accountId)

-- Set account status manually
exports["ps-banking"]:SetAccountStatus(accountId, "frozen") -- active, frozen, or closed
```

### Balance & Transaction Checks
```lua
-- Check if player has sufficient balance
local hasMoney = exports["ps-banking"]:HasSufficientBalance(source, 5000, "bank") -- or "cash"

-- Get account transactions
local transactions = exports["ps-banking"]:GetAccountTransactions(accountId, 50) -- limit: 50

-- Get unpaid bills
local bills = exports["ps-banking"]:GetUnpaidBills(identifier)
```

### Account Operations
```lua
-- Get account owner info
local owner = exports["ps-banking"]:GetAccountOwner(accountId)

-- Transfer between accounts
local success, message = exports["ps-banking"]:TransferBetweenAccounts(
    fromAccountId,
    toAccountId,
    amount,
    "Payment reason"
)

-- Add money to account
exports["ps-banking"]:AddMoney("society_accountname", 5000, "Payment received")

-- Remove money from account
exports["ps-banking"]:RemoveMoney("society_accountname", 2500, "Expense payment")

-- Get account balance
local balance = exports["ps-banking"]:GetAccountBalance("society_accountname")
```

# Features
### Overview Tab:
Includes all essential features such as managing your bills, withdrawing all money, depositing cash, transferring money weekly via Simmy, viewing the latest transactions, and handling unpaid invoices.
![image](https://cdn.discordapp.com/attachments/988759926694367262/1389410895611826176/image.png?ex=6864853b&is=686333bb&hm=27d6dd5a5f3ec9afa03f788de50bbcc8eb5f6f2d7c3da8c08c978446bf482340&)

### Bills
Enables you to send and receive bills.
![image](https://cdn.discordapp.com/attachments/988759926694367262/1389411133923917864/image.png?ex=68648574&is=686333f4&hm=be3d6fccdfd32d7868a58fa39378ad5d392edd50cab54968c1d0e11ba6ac44d4&)

### History
Displays a history of all transactions with options to delete specific transactions.
![image](https://cdn.discordapp.com/attachments/988759926694367262/1389411237624021022/image.png?ex=6864858d&is=6863340d&hm=458b0e00b55ecd00b04003772a5e688ff96a2dee0699abeb12332ea24544bbd5&)

### Accounts
Allows you to create, add, or remove accounts, rename accounts, and perform deposits or withdrawals from specific accounts.
![image](https://cdn.discordapp.com/attachments/988759926694367262/1389410758663737354/image.png?ex=6864851a&is=6863339a&hm=7500db680807d611945b95c6f1a2fb55aa20ea6c13f4694e607d52cde7aeefcc&)

### ATM Access
Deposit and withdraw from ATMs.
![image](https://cdn.discordapp.com/attachments/1081766623632949258/1388382644907151462/image.png?ex=6860c799&is=685f7619&hm=e291e94f1fdad3aed7ae53c551e3fad50c4079a77f9d5797a4d610aae12aed6d&)

# Credits
* [BachPB](https://github.com/BachPB)
