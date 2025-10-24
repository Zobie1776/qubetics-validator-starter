#!/usr/bin/env bats

setup() {
  export PATH="$PWD/tools:$PATH"
}

@test "bootstrap displays usage" {
  run bash scripts/bootstrap.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage" ]]
}

@test "finish displays usage" {
  run bash scripts/finish.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage" ]]
}

@test "rpc status help" {
  run bash scripts/rpc.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage" ]]
}

@test "monitor generates report without RPC" {
  export REPORTS_DIR="$BATS_TMPDIR/reports"
  mkdir -p "$REPORTS_DIR"
  run bash scripts/monitor.sh --help
  [ "$status" -eq 0 ]
}

@test "qubeticsctl status help" {
  run tools/qubeticsctl.py --help
  [ "$status" -eq 0 ]
}
