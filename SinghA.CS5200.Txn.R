## CS5200 – Database Management Systems
## Aaditya Kumar Singh | Spring 2026


library(RMariaDB)

# CONFIGURATION 

DB_HOST     <- Sys.getenv("DB_HOST")
DB_PORT     <- 21819
DB_NAME     <- "defaultdb"
DB_USER     <- Sys.getenv("DB_USER")
DB_PASSWORD <- Sys.getenv("DB_PASSWORD")
CA_CERT     <- "ca.pem"

# DB CONNECTION

#' Connect to the Practicum I MySQL database on Aiven
#' @return A MariaDBConnection object
connectDB <- function() {
  con <- dbConnect(
    RMariaDB::MariaDB(),
    host     = DB_HOST,
    port     = DB_PORT,
    dbname   = DB_NAME,
    user     = DB_USER,
    password = DB_PASSWORD,
    ssl.ca   = CA_CERT,
    ssl.mode = "REQUIRED"
  )
  dbExecute(con, "SET NAMES 'utf8mb4'")
  return(con)
}

#SYNTHETIC DATA GENERATION 

#' Generate five CSV files each with 500 synthetic visit records.
#' Pulls existing restaurant/server/customer/lookup data from the DB
#' so that foreign-key references are valid.
#'
#' @param outputDir directory to write CSV files into (default: "csv_data")
generateCSVFiles <- function(outputDir = "csv_data") {

  con <- connectDB()
  on.exit(dbDisconnect(con))

  #  pull reference data from DB 
  restaurants   <- dbGetQuery(con, "SELECT rid, restaurant_name FROM restaurants")
  servers       <- dbGetQuery(con, "SELECT emp_id, server_name, rid FROM servers")
  meal_types    <- dbGetQuery(con, "SELECT meal_type_id, meal_type_name FROM meal_types")
  payment_meths <- dbGetQuery(con, "SELECT payment_method_id, payment_method_name FROM payment_methods")

  # convert 64-bit integers to plain numeric
  restaurants$rid        <- as.numeric(restaurants$rid)
  servers$emp_id         <- as.numeric(servers$emp_id)
  servers$rid            <- as.numeric(servers$rid)
  meal_types$meal_type_id       <- as.numeric(meal_types$meal_type_id)
  payment_meths$payment_method_id <- as.numeric(payment_meths$payment_method_id)

  #  helper vectors 
  first_names <- c("Alex","Jordan","Taylor","Morgan","Casey","Jamie","Riley",
                   "Quinn","Avery","Skyler","Drew","Sage","Blake","Reese",
                   "Dakota","Cameron","Emery","Finley","Harper","Logan",
                   "Parker","Rowan","Sawyer","Peyton","Ellis","Hayden",
                   "Kai","Lennox","Marley","Phoenix","Remy","Sidney",
                   "Tatum","Oakley","Jessie","Kendall","Robin","Shannon",
                   "Frankie","Nico","Ariel","Carmen","Devon","Milan","Shay")
  last_names  <- c("Smith","Johnson","Williams","Brown","Jones","Garcia",
                   "Miller","Davis","Rodriguez","Martinez","Wilson","Anderson",
                   "Thomas","Taylor","Moore","Jackson","Martin","Lee",
                   "Perez","Thompson","White","Harris","Clark","Lewis",
                   "Young","Allen","King","Wright","Scott","Hill","Green",
                   "Adams","Baker","Nelson","Carter","Mitchell","Roberts",
                   "Turner","Phillips","Campbell","Parker","Evans","Edwards")

  if (!dir.exists(outputDir)) dir.create(outputDir, recursive = TRUE)

  set.seed(42)  # reproducibility

  for (fileNum in 1:5) {
    rows <- vector("list", 500)

    for (i in 1:500) {
      # pick a random restaurant
      r_idx <- sample(nrow(restaurants), 1)
      rid   <- restaurants$rid[r_idx]

      # pick a server from that restaurant
      srv_pool <- servers[servers$rid == rid, ]
      if (nrow(srv_pool) == 0) srv_pool <- servers
      s_idx      <- sample(nrow(srv_pool), 1)
      emp_id     <- srv_pool$emp_id[s_idx]
      srv_name   <- srv_pool$server_name[s_idx]

      # visit date: random date in Jan-Mar 2026
      visit_date <- as.Date("2026-01-01") + sample(0:89, 1)
      visit_date_str <- format(visit_date, "%m/%d/%Y")

      # meal type drives the visit time range
      meal <- sample(meal_types$meal_type_name, 1)
      if (meal == "Breakfast") {
        hr <- sample(6:10, 1)
      } else if (meal == "Lunch") {
        hr <- sample(11:14, 1)
      } else {
        hr <- sample(17:21, 1)
      }
      mn <- sample(0:59, 1)
      visit_time <- paste0(hr, ":", formatC(mn, width = 2, flag = "0"))

      party_size <- sample(1:8, 1)
      wait_time  <- sample(0:45, 1)

      # customer: ~70% known, 30% anonymous
      if (runif(1) < 0.7) {
        fname <- sample(first_names, 1)
        lname <- sample(last_names, 1)
        cust_name  <- paste(fname, lname)
        cust_email <- tolower(paste0(fname, ".", lname, fileNum, i, "@example.com"))
        cust_phone <- paste0("(", sample(200:999,1), ") ",
                             sample(200:999,1), "-",
                             sample(1000:9999,1))
        loyalty    <- sample(c("TRUE","FALSE"), 1)
      } else {
        cust_name  <- ""
        cust_email <- ""
        cust_phone <- ""
        loyalty    <- "FALSE"
      }

      food_bill  <- round(runif(1, 8, 120), 2)
      tip_amount <- round(food_bill * runif(1, 0.0, 0.30), 2)
      discount   <- sample(c(0, 0, 0, 5, 10, 15, 20), 1)
      pay_method <- sample(payment_meths$payment_method_name, 1)
      ordered_alc <- sample(c("TRUE","FALSE"), 1, prob = c(0.35, 0.65))
      alc_bill    <- ifelse(ordered_alc == "TRUE", round(runif(1, 5, 60), 2), 0.00)

      rows[[i]] <- data.frame(
        RestaurantID            = rid,
        ServerEmpID             = emp_id,
        ServerName              = srv_name,
        VisitDate               = visit_date_str,
        VisitTime               = visit_time,
        MealType                = meal,
        PartySize               = party_size,
        WaitTime                = wait_time,
        CustomerName            = cust_name,
        CustomerPhone           = cust_phone,
        CustomerEmail           = cust_email,
        LoyaltyMember           = loyalty,
        FoodBill                = food_bill,
        TipAmount               = tip_amount,
        FoodDiscountPercentage  = discount,
        PaymentMethod           = pay_method,
        orderedAlcohol          = ordered_alc,
        AlcoholBill             = alc_bill,
        stringsAsFactors = FALSE
      )
    }

    df <- do.call(rbind, rows)
    fname <- file.path(outputDir, paste0("txn_test_", fileNum, ".csv"))
    write.csv(df, fname, row.names = FALSE)
    cat(paste0("  Created: ", fname, " ( ", nrow(df), " rows )\n"))
  }

  cat(paste0("\nAll 5 CSV files generated in ", outputDir, "\n"))
}

#  LOAD CSV INTO DB 
#' @param csvFile  path to the CSV file
#' @param useTxn   wrap all INSERTs in BEGIN / COMMIT (default TRUE)
#' @param delay    seconds to sleep after each INSERT (default 0.05)
loadCSV <- function(csvFile, useTxn = TRUE, delay = 0.05) {

  if (!file.exists(csvFile)) stop("CSV file not found: ", csvFile)

  con <- connectDB()
  on.exit(dbDisconnect(con))

  df <- read.csv(csvFile, stringsAsFactors = FALSE)
  cat(paste0("Loading ", nrow(df), " rows from ", csvFile,
             "  [txn=", useTxn, ", delay=", delay, "s]\n"))

  # ---------- cache lookup tables ----------
  meal_types <- dbGetQuery(con, "SELECT meal_type_id, meal_type_name FROM meal_types")
  pay_meths  <- dbGetQuery(con, "SELECT payment_method_id, payment_method_name FROM payment_methods")
  meal_types$meal_type_id       <- as.numeric(meal_types$meal_type_id)
  pay_meths$payment_method_id   <- as.numeric(pay_meths$payment_method_id)

  # ---------- tracking vectors ----------
  new_visit_ids    <- c()
  new_customer_ids <- c()

  # ---------- begin transaction ----------
  if (useTxn) {
    dbExecute(con, "START TRANSACTION")
    cat("  Transaction started.\n")
  }

  tryCatch({

    for (i in seq_len(nrow(df))) {
      row <- df[i, ]

      # ---- 1. resolve customer_id ----
      customer_id <- NA
      if (!is.na(row$CustomerEmail) && nchar(trimws(row$CustomerEmail)) > 0) {
        email <- trimws(row$CustomerEmail)
        existing <- dbGetQuery(con, paste0(
          "SELECT customer_id FROM customers WHERE customer_email = ",
          dbQuoteString(con, email)
        ))
        if (nrow(existing) > 0) {
          customer_id <- as.numeric(existing$customer_id[1])
        } else {
          # insert new customer
          cust_name  <- ifelse(nchar(trimws(row$CustomerName)) > 0,
                               dbQuoteString(con, trimws(row$CustomerName)), "NULL")
          cust_phone <- ifelse(nchar(trimws(row$CustomerPhone)) > 0,
                               dbQuoteString(con, trimws(row$CustomerPhone)), "NULL")
          loyalty    <- ifelse(toupper(row$LoyaltyMember) == "TRUE", 1, 0)

          sql <- paste0(
            "INSERT INTO customers (customer_name, customer_phone, customer_email, loyalty_member) VALUES (",
            cust_name, ", ", cust_phone, ", ", dbQuoteString(con, email), ", ", loyalty, ")"
          )
          dbExecute(con, sql)
          customer_id <- as.numeric(dbGetQuery(con, "SELECT LAST_INSERT_ID() AS id")$id[1])
          new_customer_ids <- c(new_customer_ids, customer_id)
        }
      }

      # ---- 2. resolve meal_type_id ----
      mt_match <- meal_types$meal_type_id[meal_types$meal_type_name == row$MealType]
      if (length(mt_match) == 0) stop("Unknown MealType: ", row$MealType)
      meal_type_id <- mt_match[1]

      # ---- 3. resolve payment_method_id ----
      pm_match <- pay_meths$payment_method_id[pay_meths$payment_method_name == row$PaymentMethod]
      if (length(pm_match) == 0) stop("Unknown PaymentMethod: ", row$PaymentMethod)
      payment_method_id <- pm_match[1]

      # ---- 4. parse visit date/time ----
      visit_date <- format(as.Date(row$VisitDate, format = "%m/%d/%Y"), "%Y-%m-%d")
      visit_time <- row$VisitTime

      # ---- 5. other fields ----
      rid         <- as.numeric(row$RestaurantID)
      emp_id      <- as.numeric(row$ServerEmpID)
      party_size  <- as.numeric(row$PartySize)
      wait_time   <- as.numeric(row$WaitTime)
      food_bill   <- as.numeric(row$FoodBill)
      tip_amount  <- as.numeric(row$TipAmount)
      discount    <- as.numeric(row$FoodDiscountPercentage)
      ordered_alc <- ifelse(toupper(row$orderedAlcohol) == "TRUE", 1, 0)
      alc_bill    <- as.numeric(row$AlcoholBill)

      # NULL handling for emp_id and customer_id
      emp_sql  <- ifelse(is.na(emp_id) || emp_id == 0, "NULL", as.character(emp_id))
      cust_sql <- ifelse(is.na(customer_id), "NULL", as.character(customer_id))

      # ---- 6. INSERT into visits ----
      sql <- paste0(
        "INSERT INTO visits (rid, emp_id, customer_id, visit_date, visit_time, ",
        "meal_type_id, party_size, wait_time, food_bill, tip_amount, ",
        "food_discount_pct, payment_method_id, ordered_alcohol, alcohol_bill) VALUES (",
        rid, ", ", emp_sql, ", ", cust_sql, ", '", visit_date, "', '", visit_time, "', ",
        meal_type_id, ", ", party_size, ", ", wait_time, ", ", food_bill, ", ", tip_amount, ", ",
        discount, ", ", payment_method_id, ", ", ordered_alc, ", ", alc_bill, ")"
      )
      dbExecute(con, sql)
      visit_id <- as.numeric(dbGetQuery(con, "SELECT LAST_INSERT_ID() AS id")$id[1])
      new_visit_ids <- c(new_visit_ids, visit_id)

      # ---- 7. delay for concurrency testing ----
      if (delay > 0) Sys.sleep(delay)

      # progress every 50 rows
      if (i %% 50 == 0) cat(paste0("  ... ", i, " / ", nrow(df), " rows inserted\n"))
    }

    # ---------- commit ----------
    if (useTxn) {
      dbExecute(con, "COMMIT")
      cat("  Transaction committed.\n")
    }

  }, error = function(e) {
    if (useTxn) {
      cat("  ERROR - rolling back transaction.\n")
      tryCatch(dbExecute(con, "ROLLBACK"), error = function(e2) NULL)
    }
    stop(e)
  })

  #  save tracker file
  tracker_file <- paste0(csvFile, ".tracker.rds")
  saveRDS(list(visit_ids    = new_visit_ids,
               customer_ids = new_customer_ids),
          tracker_file)
  cat(paste0("  Done. Inserted ", length(new_visit_ids), " visits, ",
             length(new_customer_ids), " new customers.\n"))
  cat(paste0("  Tracker saved to: ", tracker_file, "\n"))
}

#  DELETE LOADED DATA 
#' Remove all data that was loaded from a specific CSV file.
#' Reads the .tracker.rds file produced by loadCSV().
#'
#' @param csvFile  the original CSV file path (tracker file is derived from it)
deleteLoadedData <- function(csvFile) {

  tracker_file <- paste0(csvFile, ".tracker.rds")
  if (!file.exists(tracker_file)) {
    stop("Tracker file not found: ", tracker_file,
         "\n  (Has this CSV been loaded yet?)")
  }

  tracker <- readRDS(tracker_file)
  con <- connectDB()
  on.exit(dbDisconnect(con))

  dbExecute(con, "START TRANSACTION")

  tryCatch({
    # delete visits first (child rows)
    if (length(tracker$visit_ids) > 0) {
      ids_str <- paste(as.numeric(tracker$visit_ids), collapse = ",")
      n <- dbExecute(con, paste0("DELETE FROM visits WHERE visit_id IN (", ids_str, ")"))
      cat(paste0("  Deleted ", n, " visits.\n"))
    }

    # delete new customers (only those we inserted)
    if (length(tracker$customer_ids) > 0) {
      ids_str <- paste(as.numeric(tracker$customer_ids), collapse = ",")
      n <- dbExecute(con, paste0("DELETE FROM customers WHERE customer_id IN (", ids_str, ")"))
      cat(paste0("  Deleted ", n, " customers.\n"))
    }

    dbExecute(con, "COMMIT")
    file.remove(tracker_file)
    cat("  Rollback complete. Tracker file removed.\n")

  }, error = function(e) {
    dbExecute(con, "ROLLBACK")
    stop(e)
  })
}

#  INTEGRITY VERIFICATION 

#' Run basic integrity checks on the database after concurrent loads.
#' Reports row counts, orphaned FKs, and duplicate customers.
verifyIntegrity <- function() {

  con <- connectDB()
  on.exit(dbDisconnect(con))

  cat("=== Database Integrity Check ===\n\n")

  tables <- c("restaurants","servers","customers","visits","meal_types","payment_methods")
  cat("Row counts:\n")
  for (tbl in tables) {
    n <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
    cat(paste0("  ", tbl, ": ", as.character(n), "\n"))
  }

  orphan_cust <- dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM visits v
       LEFT JOIN customers c ON v.customer_id = c.customer_id
     WHERE v.customer_id IS NOT NULL AND c.customer_id IS NULL")$n
  cat(paste0("\nOrphaned visits (bad customer_id): ", as.character(orphan_cust), "\n"))

  orphan_srv <- dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM visits v
       LEFT JOIN servers s ON v.emp_id = s.emp_id
     WHERE v.emp_id IS NOT NULL AND s.emp_id IS NULL")$n
  cat(paste0("Orphaned visits (bad emp_id):      ", as.character(orphan_srv), "\n"))

  dup_cust <- dbGetQuery(con,
    "SELECT customer_email, COUNT(*) AS cnt
     FROM customers
     WHERE customer_email IS NOT NULL
     GROUP BY customer_email
     HAVING COUNT(*) > 1")
  cat(paste0("Duplicate customer emails:         ", nrow(dup_cust), "\n"))
  if (nrow(dup_cust) > 0) {
    cat("  Examples:\n")
    head_rows <- head(dup_cust, 5)
    for (j in seq_len(nrow(head_rows))) {
      cat(paste0("    ", head_rows$customer_email[j],
                 "  (count: ", head_rows$cnt[j], ")\n"))
    }
  }

  cat("\n=== Check complete ===\n")
}

#  MAIN / CLI 

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  # ---- no args: show usage ----
  if (length(args) == 0) {
    cat("Usage:\n")
    cat("  Rscript SinghA.CS5200.Txn.R generate\n")
    cat("  Rscript SinghA.CS5200.Txn.R <csv_file> [--no-txn] [--delay <secs>]\n")
    cat("  Rscript SinghA.CS5200.Txn.R delete <csv_file>\n")
    cat("  Rscript SinghA.CS5200.Txn.R verify\n")
    cat("\nExamples:\n")
    cat("  Rscript SinghA.CS5200.Txn.R generate\n")
    cat("  Rscript SinghA.CS5200.Txn.R csv_data/txn_test_1.csv\n")
    cat("  Rscript SinghA.CS5200.Txn.R csv_data/txn_test_1.csv --no-txn --delay 0.1\n")
    cat("  Rscript SinghA.CS5200.Txn.R delete csv_data/txn_test_1.csv\n")
    cat("  Rscript SinghA.CS5200.Txn.R verify\n")
    return(invisible(NULL))
  }

  # ---- generate command ----
  if (args[1] == "generate") {
    cat("Generating 5 CSV files (500 rows each)...\n")
    generateCSVFiles()
    return(invisible(NULL))
  }

  # ---- verify command ----
  if (args[1] == "verify") {
    verifyIntegrity()
    return(invisible(NULL))
  }

  # ---- delete command ----
  if (args[1] == "delete") {
    if (length(args) < 2) stop("Specify the CSV file to delete: delete <csv_file>")
    cat(paste0("Deleting data loaded from: ", args[2], "\n"))
    deleteLoadedData(args[2])
    return(invisible(NULL))
  }

  # ---- load command (default) ----
  csvFile <- args[1]
  useTxn  <- TRUE
  delay   <- 0.05

  # parse optional flags
  i <- 2
  while (i <= length(args)) {
    if (args[i] == "--no-txn") {
      useTxn <- FALSE
    } else if (args[i] == "--delay" && i < length(args)) {
      i <- i + 1
      delay <- as.numeric(args[i])
    }
    i <- i + 1
  }

  loadCSV(csvFile, useTxn = useTxn, delay = delay)
}

# Run main
main()
