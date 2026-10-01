# Purpose : Connect to cloud MySQL and create all normalized tables (3NF schema)
# Author  : Aaditya Kumar Singh
# Semester: Spring 2026
# subtitle: CS5200 Practicum I

# Step 1: Install & load required package
if (!require("RMariaDB", quietly = TRUE))
  install.packages("RMariaDB", repos = "https://cran.r-project.org")
library(RMariaDB)

# Step 2: Store credentials in variables (easy to update in one place)
HOST   <- Sys.getenv("DB_HOST")
PORT   <- 21819
DBNAME <- "defaultdb"
USER   <- Sys.getenv("DB_USER")
PASS   <- Sys.getenv("DB_PASSWORD")

# Step 3: Open connection
con <- dbConnect(MariaDB(),
                 host                    = HOST,
                 port                    = PORT,
                 dbname                  = DBNAME,
                 user                    = USER,
                 password                = PASS,
                 ssl.ca                  = Sys.getenv("DB_SSL_CA"),
                 ssl.verify.server.cert  = FALSE
)
cat("✔ Connected to Aiven MySQL.\n")

# Step 4: Helper – run a CREATE TABLE and print confirmation
create_table <- function(con, sql, table_name) {
  dbExecute(con, sql)
  cat(paste0("  ✔ Table '", table_name, "' ready.\n"))
}

# Step 5: Create tables in dependency order
# restaurants must exist before servers (FK: rid)
# all lookup/entity tables must exist before visits (multiple FKs)

cat("\nCreating tables...\n")

# 1. restaurants – one row per physical restaurant location
create_table(con, "
  CREATE TABLE IF NOT EXISTS restaurants (
    rid               INT          NOT NULL,
    restaurant_name   VARCHAR(100) NOT NULL,
    city              VARCHAR(100) NOT NULL,
    state             VARCHAR(2)   NOT NULL,
    has_table_service BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (rid)
  ) ENGINE=InnoDB;
", "restaurants")

# 2. servers – employees who serve customers; each belongs to one restaurant
create_table(con, "
  CREATE TABLE IF NOT EXISTS servers (
    emp_id           INT          NOT NULL,
    server_name      VARCHAR(100) NOT NULL,
    birth_date       DATE         DEFAULT NULL,
    ssn              VARCHAR(11)  DEFAULT NULL,
    hourly_rate      DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    start_date_hired DATE         NOT NULL,
    end_date_hired   DATE         DEFAULT NULL,
    rid              INT          NOT NULL,
    PRIMARY KEY (emp_id),
    FOREIGN KEY (rid) REFERENCES restaurants(rid)
  ) ENGINE=InnoDB;
", "servers")

# 3. customers – identified by unique email; anonymous visits store NULL customer_id
create_table(con, "
  CREATE TABLE IF NOT EXISTS customers (
    customer_id    INT          NOT NULL AUTO_INCREMENT,
    customer_name  VARCHAR(100) DEFAULT NULL,
    customer_phone VARCHAR(20)  DEFAULT NULL,
    customer_email VARCHAR(150) DEFAULT NULL,
    loyalty_member BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY (customer_id),
    UNIQUE KEY uq_email (customer_email)
  ) ENGINE=InnoDB;
", "customers")

# 4. meal_types – lookup table to avoid repeating string values in visits
create_table(con, "
  CREATE TABLE IF NOT EXISTS meal_types (
    meal_type_id   INT         NOT NULL AUTO_INCREMENT,
    meal_type_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (meal_type_id),
    UNIQUE KEY uq_meal (meal_type_name)
  ) ENGINE=InnoDB;
", "meal_types")

# 5. payment_methods – lookup table for payment categories
create_table(con, "
  CREATE TABLE IF NOT EXISTS payment_methods (
    payment_method_id   INT         NOT NULL AUTO_INCREMENT,
    payment_method_name VARCHAR(30) NOT NULL,
    PRIMARY KEY (payment_method_id),
    UNIQUE KEY uq_payment (payment_method_name)
  ) ENGINE=InnoDB;
", "payment_methods")

# 6. visits – core fact table linking all entities for each dining event
create_table(con, "
  CREATE TABLE IF NOT EXISTS visits (
    visit_id          INT           NOT NULL AUTO_INCREMENT,
    rid               INT           NOT NULL,
    emp_id            INT           DEFAULT NULL,   -- nullable: some visits have no server
    customer_id       INT           DEFAULT NULL,   -- nullable: anonymous guests
    visit_date        DATE          NOT NULL,
    visit_time        TIME          DEFAULT NULL,
    meal_type_id      INT           NOT NULL,
    party_size        INT           NOT NULL DEFAULT 1,
    wait_time         INT           NOT NULL DEFAULT 0,
    food_bill         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    tip_amount        DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    food_discount_pct DECIMAL(5,2)  NOT NULL DEFAULT 0.00,
    payment_method_id INT           NOT NULL,
    ordered_alcohol   BOOLEAN       NOT NULL DEFAULT FALSE,
    alcohol_bill      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (visit_id),
    FOREIGN KEY (rid)               REFERENCES restaurants(rid),
    FOREIGN KEY (emp_id)            REFERENCES servers(emp_id),
    FOREIGN KEY (customer_id)       REFERENCES customers(customer_id),
    FOREIGN KEY (meal_type_id)      REFERENCES meal_types(meal_type_id),
    FOREIGN KEY (payment_method_id) REFERENCES payment_methods(payment_method_id)
  ) ENGINE=InnoDB;
", "visits")

# Step 6: Confirm all tables exist
cat("\nTables currently in database:\n")
print(dbGetQuery(con, "SHOW TABLES"))

dbDisconnect(con)
cat("\n✔ Disconnected. Schema creation complete.\n")