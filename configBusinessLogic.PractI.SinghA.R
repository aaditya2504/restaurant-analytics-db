# Program : configBusinessLogic.PractI.SinghA.R
# Purpose : Create stored procedures storeNewServer & updateServer in MySQL
# Author  : Aaditya Kumar Singh
# Semester: Spring 2026

if (!require("RMariaDB", quietly = TRUE))
  install.packages("RMariaDB", repos = "https://cran.r-project.org")
library(RMariaDB)

con <- dbConnect(MariaDB(),
                 host                   = Sys.getenv("DB_HOST"),
                 port                   = 21819,
                 dbname                 = "defaultdb",
                 user                   = Sys.getenv("DB_USER"),
                 password               = Sys.getenv("DB_PASSWORD"),
                 ssl.ca                 = Sys.getenv("DB_SSL_CA"),
                 ssl.verify.server.cert = FALSE)
cat("✔ Connected to MySQL.\n")

# Helper: safely send any SQL and immediately clear the result
safe_exec <- function(con, sql) {
  rs <- tryCatch(dbSendQuery(con, sql), error = function(e) NULL)
  if (!is.null(rs)) dbClearResult(rs)
}

# STORED PROCEDURE 1: storeNewServer

cat("\n[SP1] Creating storeNewServer...\n")

safe_exec(con, "DROP PROCEDURE IF EXISTS storeNewServer")

sp1 <- paste0(
  "CREATE PROCEDURE storeNewServer(",
  "IN p_emp_id INT, IN p_name VARCHAR(100), IN p_birth DATE,",
  "IN p_ssn VARCHAR(11), IN p_rate DECIMAL(6,2),",
  "IN p_start DATE, IN p_end DATE, IN p_rid INT, OUT p_result INT) ",
  "BEGIN ",
  "DECLARE dup_count INT DEFAULT 0; ",
  "SELECT COUNT(*) INTO dup_count FROM servers ",
  "WHERE server_name = p_name AND birth_date = p_birth; ",
  "IF dup_count > 0 THEN SET p_result = 0; ",
  "ELSE ",
  "INSERT INTO servers (emp_id, server_name, birth_date, ssn, hourly_rate, ",
  "start_date_hired, end_date_hired, rid) ",
  "VALUES (p_emp_id, p_name, p_birth, p_ssn, p_rate, p_start, p_end, p_rid); ",
  "SET p_result = 1; ",
  "END IF; ",
  "END"
)
safe_exec(con, sp1)
cat("  ✔ storeNewServer created.\n")

# STORED PROCEDURE 2: updateServer

cat("\n[SP2] Creating updateServer...\n")

safe_exec(con, "DROP PROCEDURE IF EXISTS updateServer")

sp2 <- paste0(
  "CREATE PROCEDURE updateServer(",
  "IN p_emp_id INT, IN p_name VARCHAR(100), IN p_birth DATE,",
  "IN p_ssn VARCHAR(11), IN p_rate DECIMAL(6,2),",
  "IN p_start DATE, IN p_end DATE, IN p_rid INT, OUT p_result INT) ",
  "BEGIN ",
  "DECLARE emp_exists INT DEFAULT 0; ",
  "DECLARE rid_exists INT DEFAULT 0; ",
  "DECLARE dup_count  INT DEFAULT 0; ",
  "SELECT COUNT(*) INTO emp_exists FROM servers WHERE emp_id = p_emp_id; ",
  "IF emp_exists = 0 THEN SET p_result = 0; ",
  "ELSE ",
  "SELECT COUNT(*) INTO rid_exists FROM restaurants WHERE rid = p_rid; ",
  "IF rid_exists = 0 THEN SET p_result = 0; ",
  "ELSE ",
  "SELECT COUNT(*) INTO dup_count FROM servers ",
  "WHERE server_name = p_name AND birth_date = p_birth AND emp_id <> p_emp_id; ",
  "IF dup_count > 0 THEN SET p_result = 0; ",
  "ELSE ",
  "UPDATE servers SET server_name=p_name, birth_date=p_birth, ssn=p_ssn, ",
  "hourly_rate=p_rate, start_date_hired=p_start, end_date_hired=p_end, rid=p_rid ",
  "WHERE emp_id = p_emp_id; ",
  "SET p_result = 1; ",
  "END IF; END IF; END IF; ",
  "END"
)
safe_exec(con, sp2)
cat("  ✔ updateServer created.\n")

# TESTING HARNESS

cat("\n TESTING HARNESS \n")

# Helper: compare expected vs actual and print PASS/FAIL
run_test <- function(label, expected, actual) {
  pass <- (actual == expected)
  cat(paste0("\n▶ ", label, "\n"))
  cat(paste0("  Expected: ", expected, "  |  Got: ", actual, "\n"))
  cat(paste0("  ", ifelse(pass, "✔ PASS", "✘ FAIL"), "\n"))
}

# Clean up any leftover test data from previous runs
dbExecute(con, "DELETE FROM servers WHERE emp_id IN (77701, 77702);")

# Helper: call stored procedure and clear result
call_proc <- function(con, sql) {
  rs <- tryCatch(dbSendQuery(con, sql), error = function(e) NULL)
  if (!is.null(rs)) dbClearResult(rs)
}

# T1: New server → should succeed (result = 1)
call_proc(con, "CALL storeNewServer(77701,'Singh, Aaditya','1998-07-12','111-22-3333',15.50,'2026-01-10',NULL,100,@r)")
r1 <- dbGetQuery(con, "SELECT @r AS res")$res
run_test("storeNewServer – new server (expect 1)", 1, r1)

# T2: Duplicate name + birthdate → should be rejected (result = 0)
call_proc(con, "CALL storeNewServer(77702,'Singh, Aaditya','1998-07-12','999-88-7777',10.00,'2026-02-01',NULL,100,@r)")
r2 <- dbGetQuery(con, "SELECT @r AS res")$res
run_test("storeNewServer – duplicate (expect 0)", 0, r2)

# T3: Valid update → should succeed (result = 1)
call_proc(con, "CALL updateServer(77701,'Singh, Aadi','1998-04-25','111-22-3333',18.00,'2026-01-10',NULL,100,@r)")
r3 <- dbGetQuery(con, "SELECT @r AS res")$res
run_test("updateServer – valid update (expect 1)", 1, r3)

updated <- dbGetQuery(con, "SELECT server_name, hourly_rate FROM servers WHERE emp_id = 77701")
cat(paste0("  Verified → name: '", updated$server_name, "', rate: $", updated$hourly_rate, "\n"))

# T4: Non-existent emp_id → should be rejected (result = 0)
call_proc(con, "CALL updateServer(00001,'Nobody, None','2000-01-01','000-00-0000',8.00,'2026-01-01',NULL,100,@r)")
r4 <- dbGetQuery(con, "SELECT @r AS res")$res
run_test("updateServer – emp_id not found (expect 0)", 0, r4)

# T5: Invalid restaurant ID → should be rejected (result = 0)
call_proc(con, "CALL updateServer(77701,'Singh, Aadi','1998-04-25','111-22-3333',18.00,'2026-01-10',NULL,9999,@r)")
r5 <- dbGetQuery(con, "SELECT @r AS res")$res
run_test("updateServer – invalid rid (expect 0)", 0, r5)

# Cleanup
dbExecute(con, "DELETE FROM servers WHERE emp_id IN (77701, 77702);")
cat("\n✔ Test data cleaned up.\n")

dbDisconnect(con)
cat("✔ Disconnected. Business logic setup complete.\n")