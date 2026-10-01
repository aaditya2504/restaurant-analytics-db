# Program : testDBLoading.PractI.SinghA.R
# Purpose : Validate that DB row counts and financial totals match the CSV
# Author  : Aaditya Kumar Singh
# Semester: Spring 2026

if (!require("RMariaDB", quietly = TRUE))
  install.packages("RMariaDB", repos = "https://cran.r-project.org")
library(RMariaDB)

# Connect to MySQL
con <- dbConnect(MariaDB(),
                 host                   = Sys.getenv("DB_HOST"),
                 port                   = 21819,
                 dbname                 = "defaultdb",
                 user                   = Sys.getenv("DB_USER"),
                 password               = Sys.getenv("DB_PASSWORD"),
                 ssl.ca                 = Sys.getenv("DB_SSL_CA"),
                 ssl.verify.server.cert = FALSE)
cat("✔ Connected to MySQL.\n")

# Load original CSV into R 
df.orig <- read.csv("restaurant-visits-209874.csv",
                    stringsAsFactors = FALSE,
                    na.strings = c("", "NA", "N/A"))
cat(paste0("✔ CSV loaded: ", nrow(df.orig), " rows.\n\n"))

#  Helper: print a clean PASS/FAIL test result
check <- function(label, csv_val, db_val, tol = 0) {
  pass <- abs(as.numeric(csv_val) - as.numeric(db_val)) <= tol
  cat(paste0("▶ ", label, "\n"))
  cat(paste0("  CSV : ", csv_val, "\n"))
  cat(paste0("  DB  : ", db_val,  "\n"))
  cat(paste0("  ", ifelse(pass, "✔ PASS", "✘ FAIL"), "\n\n"))
}

# TEST 1: Unique Restaurants
check(
  "TEST 1 – Unique Restaurants",
  length(unique(df.orig$RestaurantID)),
  dbGetQuery(con, "SELECT COUNT(*) AS n FROM restaurants")$n
)

#  TEST 2: Unique Customers (identified by email)
valid_emails <- unique(df.orig$CustomerEmail[
  !is.na(df.orig$CustomerEmail) & df.orig$CustomerEmail != ""])
check(
  "TEST 2 – Unique Customers (by email)",
  length(valid_emails),
  dbGetQuery(con, "SELECT COUNT(*) AS n FROM customers")$n
)

# TEST 3: Total Visits 
check(
  "TEST 3 – Total Visits (every CSV row = one visit)",
  nrow(df.orig),
  dbGetQuery(con, "SELECT COUNT(*) AS n FROM visits")$n
)

# TEST 4: Total Food Bill
check(
  "TEST 4 – Total Food Bill ($)",
  round(sum(df.orig$FoodBill, na.rm = TRUE), 2),
  round(dbGetQuery(con, "SELECT SUM(food_bill) AS s FROM visits")$s, 2),
  tol = 0.01   # allow tiny floating-point rounding difference
)

#  TEST 5: Total Alcohol Bill 
check(
  "TEST 5 – Total Alcohol Bill ($)",
  round(sum(df.orig$AlcoholBill, na.rm = TRUE), 2),
  round(dbGetQuery(con, "SELECT SUM(alcohol_bill) AS s FROM visits")$s, 2),
  tol = 0.01
)

# TEST 6: Total Tips 
check(
  "TEST 6 – Total Tips ($)",
  round(sum(df.orig$TipAmount, na.rm = TRUE), 2),
  round(dbGetQuery(con, "SELECT SUM(tip_amount) AS s FROM visits")$s, 2),
  tol = 0.01
)

# TEST 6: Total Tips 
  #round(sum(df.orig$TipAmount, na.rm = TRUE), 2),
  (dbGetQuery(con, "SELECT * FROM servers ORDER BY emp_id DESC"))
  #tol = 0.01


#  Note on Servers 
# Server count comes from the SQLite source file, not the CSV.
# It may differ from unique ServerEmpIDs in the CSV because SQLite is
# the authoritative source for employee records.
db_srv  <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM servers")$n
csv_srv <- length(unique(df.orig$ServerEmpID[
  !is.na(df.orig$ServerEmpID) & df.orig$ServerEmpID != ""]))
cat(paste0("▶ Server count note\n"))
cat(paste0("  CSV unique EmpIDs : ", csv_srv, "\n"))
cat(paste0("  DB (from SQLite)  : ", db_srv,  "\n"))
cat("  (Difference expected – SQLite is authoritative source for servers)\n\n")

dbDisconnect(con)
cat("✔ All tests complete. Disconnected.\n")