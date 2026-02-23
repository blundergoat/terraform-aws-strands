#!/usr/bin/env bash
# =============================================================================
# Terraform Helper Script - strands-agent-stack
# =============================================================================
#
# Simplifies common Terraform operations.
#
# USAGE:
#   ./scripts/terraform.sh <command> [options]
#
# COMMANDS:
#   init        Initialize Terraform (downloads providers, configures backend)
#   plan        Preview changes without applying
#   apply       Apply changes (with auto-approve option)
#   destroy     Destroy all resources (with confirmation)
#   output      Show Terraform outputs
#   validate    Validate configuration files
#   fmt         Format Terraform files
#   state       Manage Terraform state
#   console     Interactive Terraform console
#   refresh     Refresh state from AWS
#   import      Import existing resources
#   unlock      Force unlock state (use with caution)
#
# OPTIONS:
#   -y, --yes       Auto-approve (skip confirmation prompts)
#   -h, --help      Show this help message
#   --bootstrap     Run against bootstrap module instead of main
#
# ENVIRONMENT VARIABLES:
#   AWS_PROFILE     AWS CLI profile to use (default: read from environment)
#   AWS_REGION      AWS region (default: us-east-1)
#
# EXAMPLES:
#   ./scripts/terraform.sh init
#   ./scripts/terraform.sh plan
#   ./scripts/terraform.sh apply -y
#   ./scripts/terraform.sh --bootstrap init
#   ./scripts/terraform.sh --bootstrap apply
#   AWS_PROFILE=my-profile ./scripts/terraform.sh plan
#
# =============================================================================

set -euo pipefail

# Configuration - override via environment variables
AWS_PROFILE_NAME="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MAIN_DIR="$PROJECT_ROOT/terraform/environments/main"
BOOTSTRAP_DIR="$PROJECT_ROOT/terraform/bootstrap"

# Default to main environment
TF_DIR="$MAIN_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Export AWS profile and region if set
if [[ -n "$AWS_PROFILE_NAME" ]]; then
    export AWS_PROFILE="$AWS_PROFILE_NAME"
fi
export AWS_DEFAULT_REGION="$AWS_REGION"

# Parse options
AUTO_APPROVE=""
USE_BOOTSTRAP=false
EXTRA_ARGS=()

show_help() {
    echo -e "${BOLD}${BLUE}Terraform Helper Script - terraform-aws-strands${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "  ./scripts/terraform.sh <command> [options]"
    echo ""
    echo -e "${BOLD}COMMANDS:${NC}"
    echo -e "  ${GREEN}init${NC}        Initialize Terraform (downloads providers, configures backend)"
    echo -e "  ${GREEN}plan${NC}        Preview changes without applying"
    echo -e "  ${GREEN}apply${NC}       Apply changes (with auto-approve option)"
    echo -e "  ${GREEN}destroy${NC}     Destroy all resources (requires confirmation)"
    echo -e "  ${GREEN}output${NC}      Show Terraform outputs"
    echo -e "  ${GREEN}validate${NC}    Validate configuration files"
    echo -e "  ${GREEN}fmt${NC}         Format Terraform files"
    echo -e "  ${GREEN}state${NC}       Manage Terraform state (list, show, mv, rm)"
    echo -e "  ${GREEN}console${NC}     Interactive Terraform console"
    echo -e "  ${GREEN}refresh${NC}     Refresh state from AWS"
    echo -e "  ${GREEN}import${NC}      Import existing resources"
    echo -e "  ${GREEN}unlock${NC}      Force unlock state (use with caution)"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "  -y, --yes       Auto-approve (skip confirmation prompts)"
    echo "  -h, --help      Show this help message"
    echo "  --bootstrap     Run against bootstrap module instead of prod"
    echo ""
    echo -e "${BOLD}ENVIRONMENT VARIABLES:${NC}"
    echo "  AWS_PROFILE     AWS CLI profile to use"
    echo "  AWS_REGION      AWS region (default: us-east-1)"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "  ./scripts/terraform.sh plan -var-file=staging.tfvars"
    echo "  ./scripts/terraform.sh plan -var-file=production.tfvars"
    echo "  AWS_PROFILE=prod ./scripts/terraform.sh apply -var-file=production.tfvars"
    echo "  ./scripts/terraform.sh output"
    echo "  ./scripts/terraform.sh state list"
    echo "  ./scripts/terraform.sh --bootstrap init"
    echo ""
    echo -e "${BOLD}ENVIRONMENT:${NC}"
    echo "  AWS_PROFILE: ${AWS_PROFILE_NAME:-<not set>}"
    echo "  AWS_REGION:  $AWS_REGION"
    echo "  TF_DIR:      $TF_DIR"
    echo ""
    echo -e "${BOLD}WORKFLOW:${NC}"
    echo "  1. ./scripts/terraform.sh --bootstrap init && ./scripts/terraform.sh --bootstrap apply"
    echo "  2. ./scripts/terraform.sh init"
    echo "  3. ./scripts/terraform.sh plan -var-file=staging.tfvars"
    echo "  4. ./scripts/terraform.sh apply -var-file=staging.tfvars"
    echo ""
}

check_credentials() {
    if aws sts get-caller-identity &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_initialized() {
    if [[ ! -d "$TF_DIR/.terraform" ]]; then
        echo -e "${YELLOW}Terraform not initialized. Running init first...${NC}"
        echo ""
        run_terraform init
        echo ""
    fi
}

run_terraform() {
    local cmd="$1"
    shift

    echo -e "${BLUE}Running: terraform $cmd $*${NC}"
    echo -e "${CYAN}Directory: $TF_DIR${NC}"
    echo -e "${CYAN}Profile: ${AWS_PROFILE_NAME:-<default>} | Region: $AWS_REGION${NC}"
    echo ""

    terraform -chdir="$TF_DIR" "$cmd" "$@"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            AUTO_APPROVE="-auto-approve"
            shift
            ;;
        --bootstrap)
            USE_BOOTSTRAP=true
            TF_DIR="$BOOTSTRAP_DIR"
            shift
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#EXTRA_ARGS[@]} -eq 0 ]]; then
    show_help
    exit 0
fi

COMMAND="${EXTRA_ARGS[0]}"
unset 'EXTRA_ARGS[0]'
EXTRA_ARGS=("${EXTRA_ARGS[@]}")

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    echo "Install it from: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! check_credentials; then
    echo -e "${YELLOW}AWS credentials not found or expired${NC}"
    echo ""
    if [[ -n "$AWS_PROFILE_NAME" ]]; then
        echo "To fix this, run:"
        echo "  aws sso login --profile $AWS_PROFILE_NAME"
    else
        echo "Set AWS_PROFILE or configure credentials:"
        echo "  export AWS_PROFILE=your-profile"
        echo "  aws sso login --profile your-profile"
    fi
    echo ""
    exit 1
fi

# Execute the command
case $COMMAND in
    init)
        if [[ "$USE_BOOTSTRAP" == true ]]; then
            run_terraform init "${EXTRA_ARGS[@]}"
        else
            if [[ -f "$TF_DIR/backend.hcl" ]]; then
                run_terraform init -backend-config=backend.hcl "${EXTRA_ARGS[@]}"
            else
                echo -e "${YELLOW}Warning: backend.hcl not found${NC}"
                echo "Copy backend.hcl.example to backend.hcl and configure it."
                echo ""
                run_terraform init "${EXTRA_ARGS[@]}"
            fi
        fi
        ;;

    plan)
        check_initialized
        run_terraform plan "${EXTRA_ARGS[@]}"
        ;;

    apply)
        check_initialized
        if [[ -n "$AUTO_APPROVE" ]]; then
            run_terraform apply "$AUTO_APPROVE" "${EXTRA_ARGS[@]}"
        else
            run_terraform apply "${EXTRA_ARGS[@]}"
        fi
        ;;

    destroy)
        check_initialized
        echo -e "${RED}${BOLD}WARNING: This will destroy all infrastructure!${NC}"
        echo ""
        if [[ -n "$AUTO_APPROVE" ]]; then
            run_terraform destroy "$AUTO_APPROVE" "${EXTRA_ARGS[@]}"
        else
            run_terraform destroy "${EXTRA_ARGS[@]}"
        fi
        ;;

    output)
        check_initialized
        run_terraform output "${EXTRA_ARGS[@]}"
        ;;

    validate)
        run_terraform validate "${EXTRA_ARGS[@]}"
        ;;

    fmt)
        echo -e "${BLUE}Formatting Terraform files...${NC}"
        terraform fmt -recursive "$PROJECT_ROOT/terraform"
        echo -e "${GREEN}Done!${NC}"
        ;;

    state)
        check_initialized
        run_terraform state "${EXTRA_ARGS[@]}"
        ;;

    console)
        check_initialized
        run_terraform console "${EXTRA_ARGS[@]}"
        ;;

    refresh)
        check_initialized
        run_terraform refresh "${EXTRA_ARGS[@]}"
        ;;

    import)
        check_initialized
        run_terraform import "${EXTRA_ARGS[@]}"
        ;;

    unlock)
        if [[ ${#EXTRA_ARGS[@]} -eq 0 ]]; then
            echo -e "${RED}Error: Lock ID required${NC}"
            echo "Usage: ./scripts/terraform.sh unlock <LOCK_ID>"
            exit 1
        fi
        echo -e "${YELLOW}Force unlocking state...${NC}"
        run_terraform force-unlock "${EXTRA_ARGS[@]}"
        ;;

    *)
        check_initialized
        run_terraform "$COMMAND" "${EXTRA_ARGS[@]}"
        ;;
esac
