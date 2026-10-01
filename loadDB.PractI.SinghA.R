# Program : loadDB.PractI.SinghA.R
# Purpose : Load data from CSV + SQLite into the cloud MySQL database
# Author  : Aaditya Kumar Singh
# Semester: Spring 2026

# Step 1: Install & load packages
for (pkg in c("RMariaDB", "RSQLite")) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE))
    install.packages(pkg, repos = "https://cran.r-project.org")
  library(pkg, character.only = TRUE)
}

# Step 2: Open database connections
mycon <- dbConnect(MariaDB(),
                   host                   = Sys.getenv("DB_HOST"),
                   port                   = 21819,
                   dbname                 = "defaultdb",
                   user                   = Sys.getenv("DB_USER"),
                   password               = Sys.getenv("DB_PASSWORD"),
                   ssl.ca                 = Sys.getenv("DB_SSL_CA"),
                   ssl.verify.server.cert = FALSE)
cat("✔ MySQL connected.\n")

sqlite_con <- dbConnect(SQLite(), "restaurants-db-02102026.sqlitedb")
cat("✔ SQLite connected.\n")

# Step 3: Load CSV into R dataframe
# df.orig holds ALL raw visit data from the original CSV data dump
df.orig <- read.csv("restaurant-visits-209874.csv",
                    stringsAsFactors = FALSE,
                    na.strings = c("", "NA", "N/A"))
cat(paste0("✔ CSV loaded: ", nrow(df.orig), " rows.\n"))

# Helper Functions

# Wrap a value in SQL single quotes; returns NULL string for missing values
to_sql_str <- function(val) {
  if (is.na(val) || is.null(val) || val == "") return("NULL")
  val <- gsub("'", "\\\\'", as.character(val))  # escape single quotes in data
  paste0("'", val, "'")
}

# Parse dates that may arrive in m/d/yyyy OR yyyy-mm-dd format
safe_date <- function(d) {
  if (is.na(d) || d == "" || d == "0000-00-00") return(NA)
  parsed <- tryCatch(as.Date(d, "%m/%d/%Y"), error = function(e) NA)
  if (!is.na(parsed)) return(as.character(parsed))
  parsed <- tryCatch(as.Date(d, "%Y-%m-%d"), error = function(e) NA)
  if (!is.na(parsed)) return(as.character(parsed))
  NA
}

# Insert rows in batches to reduce network round-trips (much faster than row-by-row)
# Uses dbExecute() instead of dbSendStatement() to auto-clear results and avoid
# "Cancelling previous query" warnings
batch_insert <- function(con, table, cols, rows, batch = 500) {
  col_str <- paste0("(", paste(cols, collapse = ", "), ")")
  n <- length(rows)
  for (i in seq(1, n, by = batch)) {
    chunk <- rows[i:min(i + batch - 1, n)]
    vals  <- paste(
      sapply(chunk, function(r) paste0("(", paste(r, collapse = ","), ")")),
      collapse = ",\n"
    )
    dbExecute(con, paste0("INSERT INTO ", table, " ", col_str,
                          " VALUES ", vals, ";"))
  }
  cat(paste0("  ✔ ", n, " rows inserted into '", table, "'\n"))
}

# 1. Load Restaurants (from SQLite)
cat("\n[1/6] Loading restaurants from SQLite...\n")
rest_df <- dbGetQuery(sqlite_con, "SELECT * FROM restaurants")

rest_rows <- lapply(seq_len(nrow(rest_df)), function(i) {
  r <- rest_df[i, ]
  c(as.character(r$rID),
    to_sql_str(r$RestaurantName),
    to_sql_str(r$City),
    to_sql_str(r$State),
    ifelse(tolower(r$hasTableService) == "yes", "TRUE", "FALSE"))
})
batch_insert(mycon, "restaurants",
             c("rid", "restaurant_name", "city", "state", "has_table_service"),
             rest_rows)

# 2. Load Servers (from SQLite, deduplicated by most recent hire date)
cat("\n[2/6] Loading servers from SQLite...\n")

# Some employees appear multiple times (e.g., transferred between restaurants).
# Keep only the most recent record per EmpID.
srv_df <- dbGetQuery(sqlite_con, "
  SELECT s.*
  FROM servers s
  INNER JOIN (
    SELECT EmpID, MAX(StartDateHired) AS latest
    FROM servers
    GROUP BY EmpID
  ) t ON s.EmpID = t.EmpID AND s.StartDateHired = t.latest
")
srv_df <- srv_df[!duplicated(srv_df$EmpID), ]   # remove any remaining ties
cat(paste0("  ", nrow(srv_df), " unique servers after deduplication.\n"))

srv_rows <- lapply(seq_len(nrow(srv_df)), function(i) {
  s <- srv_df[i, ]
  c(as.character(s$EmpID),
    to_sql_str(s$ServerName),
    to_sql_str(safe_date(s$BirthDate)),
    to_sql_str(s$SSN),
    as.character(ifelse(is.na(s$HourlyRate), 0, s$HourlyRate)),
    to_sql_str(safe_date(s$StartDateHired)),
    to_sql_str(safe_date(s$EndDateHired)),
    as.character(s$rID))
})
batch_insert(mycon, "servers",
             c("emp_id", "server_name", "birth_date", "ssn", "hourly_rate",
               "start_date_hired", "end_date_hired", "rid"),
             srv_rows)

# 3. Load Meal Types (lookup – unique values from CSV)
cat("\n[3/6] Loading meal types...\n")
meal_types <- sort(unique(na.omit(df.orig$MealType)))
for (mt in meal_types)
  dbExecute(mycon, paste0("INSERT INTO meal_types (meal_type_name) VALUES (",
                          to_sql_str(mt), ");"))
cat(paste0("  ✔ ", length(meal_types), " meal types inserted.\n"))

# Build name → id lookup map (used when building visit rows)
mt_map    <- dbGetQuery(mycon, "SELECT meal_type_id, meal_type_name FROM meal_types")
mt_lookup <- setNames(mt_map$meal_type_id, mt_map$meal_type_name)

# 4. Load Payment Methods (lookup – unique values from CSV)
cat("\n[4/6] Loading payment methods...\n")
pay_methods <- sort(unique(na.omit(df.orig$PaymentMethod)))
for (pm in pay_methods)
  dbExecute(mycon, paste0("INSERT INTO payment_methods (payment_method_name) VALUES (",
                          to_sql_str(pm), ");"))
cat(paste0("  ✔ ", length(pay_methods), " payment methods inserted.\n"))

pm_map    <- dbGetQuery(mycon, "SELECT payment_method_id, payment_method_name FROM payment_methods")
pm_lookup <- setNames(pm_map$payment_method_id, pm_map$payment_method_name)

# 5. Load Customers (unique emails from CSV; anonymous rows skipped)
cat("\n[5/6] Loading customers...\n")
has_email <- !is.na(df.orig$CustomerEmail) & df.orig$CustomerEmail != ""
cust_df   <- df.orig[has_email, c("CustomerName", "CustomerPhone",
                                  "CustomerEmail", "LoyaltyMember")]
cust_df   <- cust_df[!duplicated(cust_df$CustomerEmail), ]
cat(paste0("  ", nrow(cust_df), " unique customers with email.\n"))

cust_rows <- lapply(seq_len(nrow(cust_df)), function(i) {
  r <- cust_df[i, ]
  c(to_sql_str(r$CustomerName),
    to_sql_str(r$CustomerPhone),
    to_sql_str(r$CustomerEmail),
    ifelse(isTRUE(r$LoyaltyMember), "TRUE", "FALSE"))
})
batch_insert(mycon, "customers",
             c("customer_name", "customer_phone", "customer_email", "loyalty_member"),
             cust_rows)

# Build email → customer_id lookup map
cust_map    <- dbGetQuery(mycon, "SELECT customer_id, customer_email FROM customers")
cust_lookup <- setNames(cust_map$customer_id, cust_map$customer_email)

# 6. Load Visits (main fact table – all rows from CSV)
cat("\n[6/6] Loading visits (this may take a few minutes)...\n")

# Pre-process all columns into vectors for speed (avoids slow per-row access)
v_rid   <- df.orig$RestaurantID
v_emp   <- ifelse(is.na(df.orig$ServerEmpID) | df.orig$ServerEmpID == "",
                  NA, df.orig$ServerEmpID)
v_email <- ifelse(is.na(df.orig$CustomerEmail) | df.orig$CustomerEmail == "",
                  NA, df.orig$CustomerEmail)
v_cust  <- ifelse(is.na(v_email), NA, cust_lookup[v_email])

# Sentinel value handling:
#   "0000-00-00" dates  → replaced with placeholder 1970-01-01
#   party size = 99     → unknown, default to 1
v_date  <- ifelse(is.na(df.orig$VisitDate) | df.orig$VisitDate == "0000-00-00",
                  "1970-01-01", df.orig$VisitDate)
v_time  <- ifelse(is.na(df.orig$VisitTime) | df.orig$VisitTime == "",
                  NA, df.orig$VisitTime)
v_mt    <- mt_lookup[df.orig$MealType]
v_party <- ifelse(is.na(df.orig$PartySize) | df.orig$PartySize == 99,
                  1, df.orig$PartySize)
v_wait  <- ifelse(is.na(df.orig$WaitTime), 0, df.orig$WaitTime)
v_food  <- ifelse(is.na(df.orig$FoodBill), 0, df.orig$FoodBill)
v_tip   <- ifelse(is.na(df.orig$TipAmount), 0, df.orig$TipAmount)
v_disc  <- ifelse(is.na(df.orig$FoodDiscountPercentage), 0, df.orig$FoodDiscountPercentage)
v_pm    <- pm_lookup[df.orig$PaymentMethod]
v_alc   <- ifelse(tolower(df.orig$orderedAlcohol) == "yes", "TRUE", "FALSE")
v_abill <- ifelse(is.na(df.orig$AlcoholBill), 0, df.orig$AlcoholBill)

cat("  Inserting visits in chunks to avoid memory crash...\n")
n          <- nrow(df.orig)
chunk_size <- 5000   # process 5000 rows at a time
col_str    <- "(rid, emp_id, customer_id, visit_date, visit_time,
                meal_type_id, party_size, wait_time, food_bill,
                tip_amount, food_discount_pct, payment_method_id,
                ordered_alcohol, alcohol_bill)"

chunks <- seq(1, n, by = chunk_size)
cat(paste0("  Total rows: ", n, " | Chunks: ", length(chunks), "\n"))

for (start in chunks) {
  end   <- min(start + chunk_size - 1, n)
  idx   <- start:end
  
  # Build only this chunk's rows
  rows <- mapply(function(i) {
    paste0("(",
           as.character(v_rid[i]),   ",",
           ifelse(is.na(v_emp[i]),   "NULL", as.character(v_emp[i])),  ",",
           ifelse(is.na(v_cust[i]),  "NULL", as.character(v_cust[i])), ",",
           to_sql_str(v_date[i]),    ",",
           ifelse(is.na(v_time[i]),  "NULL", to_sql_str(v_time[i])),   ",",
           as.character(v_mt[i]),    ",",
           as.character(v_party[i]), ",",
           as.character(v_wait[i]),  ",",
           as.character(v_food[i]),  ",",
           as.character(v_tip[i]),   ",",
           as.character(v_disc[i]),  ",",
           as.character(v_pm[i]),    ",",
           v_alc[i],                 ",",
           as.character(v_abill[i]),
           ")")
  }, idx, SIMPLIFY = TRUE)
  
  sql <- paste0("INSERT INTO visits ", col_str, " VALUES ",
                paste(rows, collapse = ",\n"), ";")
  dbExecute(mycon, sql)
  
  # Print progress every 10 chunks
  if ((which(chunks == start) %% 10) == 0 || end == n)
    cat(paste0("  ✔ Inserted rows ", start, " to ", end, "\n"))
}
cat(paste0("  ✔ All ", n, " visits inserted.\n"))

# Final row count verification
cat("\n── Row counts in database ──\n")
for (tbl in c("restaurants", "servers", "customers",
              "meal_types", "payment_methods", "visits")) {
  cnt <- dbGetQuery(mycon, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
  cat(paste0("  ", tbl, ": ", cnt, "\n"))
}

dbDisconnect(sqlite_con)
dbDisconnect(mycon)
cat("\n✔ All data loaded. Disconnected from all databases.\n")