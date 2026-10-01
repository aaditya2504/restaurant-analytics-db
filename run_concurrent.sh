#!/bin/bash
## -
## run_concurrent.sh
## Launches 4 instances of SinghA.CS5200.Txn.R in parallel, each
## loading a different CSV file. Pass --no-txn to disable transactions.
##
## Usage:
##   ./run_concurrent.sh              # with transactions (default)
##   ./run_concurrent.sh --no-txn     # without transactions
## -

TXN_FLAG=""
if [ "$1" == "--no-txn" ]; then
  TXN_FLAG="--no-txn"
  echo ">>> Running WITHOUT transactions"
else
  echo ">>> Running WITH transactions"
fi

DELAY="--delay 0.05"

echo "Starting 4 concurrent loads at $(date)..."
echo "-------------------------------------------"

Rscript SinghA.CS5200.Txn.R csv_data/txn_test_1.csv $TXN_FLAG $DELAY > log_csv1.txt 2>&1 &
PID1=$!
echo "  CSV 1 started (PID $PID1)"

Rscript SinghA.CS5200.Txn.R csv_data/txn_test_2.csv $TXN_FLAG $DELAY > log_csv2.txt 2>&1 &
PID2=$!
echo "  CSV 2 started (PID $PID2)"

Rscript SinghA.CS5200.Txn.R csv_data/txn_test_3.csv $TXN_FLAG $DELAY > log_csv3.txt 2>&1 &
PID3=$!
echo "  CSV 3 started (PID $PID3)"

Rscript SinghA.CS5200.Txn.R csv_data/txn_test_4.csv $TXN_FLAG $DELAY > log_csv4.txt 2>&1 &
PID4=$!
echo "  CSV 4 started (PID $PID4)"

echo "-------------------------------------------"
echo "Waiting for all processes to finish..."

wait $PID1; echo "  CSV 1 done (exit $?)"
wait $PID2; echo "  CSV 2 done (exit $?)"
wait $PID3; echo "  CSV 3 done (exit $?)"
wait $PID4; echo "  CSV 4 done (exit $?)"

echo "-------------------------------------------"
echo "All loads completed at $(date)"
echo "Check log_csv1.txt – log_csv4.txt for details."
echo ""
echo "Running integrity check..."
Rscript SinghA.CS5200.Txn.R verify
