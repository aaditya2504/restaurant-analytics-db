# Program : deleteDB.PractI.SinghA.R
# Purpose : Drop all tables to reset the database (run before re-running createDB)
# Author  : Aaditya Kumar Singh
# Semester: Spring 2026

if (!require("RMariaDB", quietly = TRUE))
  install.packages("RMariaDB", repos = "https://cran.r-project.org")
library(RMariaDB)

# Connect 
con <- dbConnect(MariaDB(),
                 host                   = Sys.getenv("DB_HOST"),
                 port                   = 21819,
                 dbname                 = "defaultdb",
                 user                   = Sys.getenv("DB_USER"),
                 password               = Sys.getenv("DB_PASSWORD"),
                 ssl.ca                 = Sys.getenv("DB_SSL_CA"),
                 ssl.verify.server.cert = FALSE)
cat("✔ Connected to MySQL.\n")

# Disable FK checks so tables can be dropped in any order
dbSendStatement(con, "SET FOREIGN_KEY_CHECKS = 0;")

# Drop child tables first, then parent tables
tables_to_drop <- c("visits", "customers", "servers",
                    "meal_types", "payment_methods", "restaurants")

cat("\nDropping tables...\n")
for (tbl in tables_to_drop) {
  dbSendStatement(con, paste0("DROP TABLE IF EXISTS ", tbl, ";"))
  cat(paste0("  ✔ Dropped '", tbl, "'\n"))
}

# Re-enable FK checks
dbSendStatement(con, "SET FOREIGN_KEY_CHECKS = 1;")

# Verify the database is now empty
remaining <- dbGetQuery(con, "SHOW TABLES")
if (nrow(remaining) == 0) {
  cat("\n✔ All tables dropped. Database is clean and ready.\n")
} else {
  cat("\n⚠ Warning – these tables still remain:\n")
  print(remaining)
}

dbDisconnect(con)
cat("✔ Disconnected.\n")