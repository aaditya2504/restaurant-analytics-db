# Observations
## Aaditya Kumar Singh | CS5200 | Spring 2026

### Test Setup
- Aiven-hosted MySQL database (InnoDB engine) from Practicum I, already populated with ~209,874 visit records.
- Five synthetic CSV files generated (500 rows each, 2,500 total new records).
- Four CSV files loaded concurrently from four separate terminal sessions.
- Each INSERT had a 0.05-second delay to extend the transaction window and increase the chance of overlap.

### With Transactions (START TRANSACTION / COMMIT)

All four concurrent loads completed successfully. The `verify` integrity check confirmed:
- All 2,000 new visits were inserted (4 × 500).
- No orphaned foreign keys (every visit referenced a valid restaurant, server, and customer).
- No duplicate customer emails — each concurrent process correctly handled customer lookups and inserts without race conditions at the InnoDB level.
- When one load was intentionally made to fail mid-way (by inserting a bad restaurant ID), the ROLLBACK cleanly removed all rows from that file's transaction, leaving the database in a consistent state.

InnoDB's row-level locking and MVCC (Multi-Version Concurrency Control) ensured that concurrent transactions were isolated from each other. Each process saw a consistent snapshot of the data, and commits were applied atomically.

### Without Transactions (--no-txn flag)

Running the same four loads concurrently without transaction wrapping produced different results:
- All 2,000 rows were still inserted (no errors in this run), since the data was designed to avoid FK violations.
- However, **duplicate customer records** appeared in the customers table. When two processes simultaneously checked for the same customer email (SELECT), both found no match and both did an INSERT — a classic **read-then-write race condition**. The `verify` command flagged these duplicates.
- If a failure occurred mid-load (e.g., network timeout after row 300), the first 300 rows remained in the database with no way to automatically roll them back — a **partial insert**. The database was left in an inconsistent state where some rows from the CSV were loaded and others were not.

### Key Takeaway

Transactions provide **atomicity** (all-or-nothing commits) and **isolation** (preventing race conditions on shared data like the customers table). Without them, concurrent writes can cause data integrity issues such as duplicate records and partial inserts that are difficult to detect and recover from. This is especially critical in multi-user, production environments where simultaneous writes to the same tables are common.
