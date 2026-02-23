#!/usr/bin/env bash
# =============================================================================
# Preflight Checks - Validate Terraform configuration without deploying
# =============================================================================
#
# Runs format checks and validation against all modules. No AWS credentials
# or backend configuration required.
#
# USAGE:
#   ./scripts/preflight-checks.sh
#
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_ROOT="$PROJECT_ROOT/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}PASS${NC}"
FAIL="${RED}FAIL${NC}"
ERRORS=0

log() { echo -e "${BLUE}[preflight]${NC} $*"; }
result() {
    if [[ $1 -eq 0 ]]; then
        echo -e "  ${PASS}  $2"
    else
        echo -e "  ${FAIL}  $2"
        ERRORS=$((ERRORS + 1))
    fi
}

# Check terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}Terraform Preflight Checks${NC}"
echo -e "──────────────────────────────────"
echo ""

# ── Format check ────────────────────────────────────────────────────
log "Checking format..."
terraform fmt -check -recursive "$TF_ROOT" > /dev/null 2>&1
result $? "terraform fmt"

# ── Validate bootstrap ──────────────────────────────────────────────
log "Validating bootstrap module..."
pushd "$TF_ROOT/bootstrap" > /dev/null
terraform init -backend=false > /dev/null 2>&1
terraform validate > /dev/null 2>&1
result $? "bootstrap"
popd > /dev/null

# ── Validate main environment ───────────────────────────────────────
log "Validating main environment..."
pushd "$TF_ROOT/environments/main" > /dev/null
terraform init -backend=false > /dev/null 2>&1
terraform validate > /dev/null 2>&1
result $? "environments/main"
popd > /dev/null

# ── Validate individual modules ─────────────────────────────────────
log "Validating modules..."
for module_dir in "$TF_ROOT"/modules/*/; do
    module_name=$(basename "$module_dir")
    pushd "$module_dir" > /dev/null
    terraform init -backend=false > /dev/null 2>&1
    terraform validate > /dev/null 2>&1
    result $? "modules/$module_name"
    popd > /dev/null
done

# ── Summary ─────────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All checks passed.${NC}"
else
    echo -e "${RED}${BOLD}${ERRORS} check(s) failed.${NC}"
fi
echo ""

exit $ERRORS
