#!/usr/bin/env bash
# UI density probe (P2 baseline) — see docs/ui-principles.md
# Usage: bash tools/density-report.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

OUT=/tmp/nkb-density
VIEWPORTS=${VIEWPORTS:-"1440x900,375x812"}
ROUTES=${ROUTES:-"/admin,/admin/customers,/admin/follow-ups,/admin/usage,/admin/wellness-records,/admin/salons,/admin/interactions"}
JSON=${JSON:-0}
mkdir -p "$OUT"

VIEWPORTS="$VIEWPORTS" ROUTES="$ROUTES" OUT="$OUT" JSON="$JSON" \
  timeout 600 node tools/density-probe.mjs
