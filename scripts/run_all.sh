#!/bin/sh
# Runs stages 1,2,3 and then the combined stage 0 (writes reports/*.txt). Any failure => nonzero exit.
# usage: scripts/run_all.sh [iverilog|riviera]      env: SEED, WAVES
SIM=${1:-iverilog}; D=$(dirname "$0"); RC=0
for s in 1 2 3 0; do
  echo "================ stage $s ================"
  "$D/run.sh" $s "$SIM" || { echo ">>> stage $s FAILED"; RC=1; }
done
[ $RC -eq 0 ] && echo "ALL STAGES PASSED" || echo "REGRESSION FAILED"
exit $RC
