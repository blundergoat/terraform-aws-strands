#!/usr/bin/env bash
# =============================================================================
# Deploy Script - Build and Push Docker Images to ECR
# =============================================================================
#
# Builds Docker images and pushes them to ECR, then forces an ECS service
# redeployment. Works with any application using this infrastructure stack.
#
# USAGE:
#   ./scripts/deploy.sh              # Build and deploy both images
#   ./scripts/deploy.sh agent        # Build and deploy agent only
#   ./scripts/deploy.sh app          # Build and deploy app only
#
# ENVIRONMENT VARIABLES:
#   AWS_PROFILE       AWS CLI profile to use
#   AWS_REGION        AWS region (default: us-east-1)
#   IMAGE_TAG         Docker image tag (default: latest)
#   APP_DIR           Path to the application repo (default: current directory)
#   AGENT_DOCKERFILE  Path to agent Dockerfile (default: $APP_DIR/strands_agents/Dockerfile)
#   AGENT_CONTEXT     Docker build context for agent (default: $APP_DIR/strands_agents)
#   APP_DOCKERFILE    Path to app Dockerfile (default: $APP_DIR/Dockerfile)
#   APP_CONTEXT       Docker build context for app (default: $APP_DIR)
#
# PREREQUISITES:
#   - AWS CLI configured with correct profile
#   - Docker running
#   - Terraform applied (ECR repos must exist)
#
# =============================================================================

set -euo pipefail

# Configuration - override via environment variables
AWS_PROFILE_NAME="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$INFRA_ROOT/terraform/environments/main"
IMAGE_TAG="${IMAGE_TAG:-latest}"
APP_DIR="${APP_DIR:-.}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ -n "$AWS_PROFILE_NAME" ]]; then
    export AWS_PROFILE="$AWS_PROFILE_NAME"
fi
export AWS_DEFAULT_REGION="$AWS_REGION"

# What to deploy
TARGET="${1:-all}"
if [[ "$TARGET" != "all" && "$TARGET" != "agent" && "$TARGET" != "app" ]]; then
    error "Invalid target: $TARGET (must be all, agent, or app)"
fi

log() { echo -e "${BLUE}[deploy]${NC} $*"; }
success() { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $*"; }
error() { echo -e "${RED}[deploy]${NC} $*"; exit 1; }

# Get ECR repository URLs from Terraform outputs
get_tf_output() {
    terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null
}

# Verify prerequisites
log "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    error "Terraform is not installed"
fi

if ! command -v docker &> /dev/null; then
    error "Docker is not installed"
fi

if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed"
fi

if ! aws sts get-caller-identity &> /dev/null; then
    if [[ -n "$AWS_PROFILE_NAME" ]]; then
        error "AWS credentials not found or expired. Run: aws sso login --profile $AWS_PROFILE_NAME"
    else
        error "AWS credentials not found or expired. Set AWS_PROFILE and run: aws sso login"
    fi
fi

# Get ECR URLs from Terraform
log "Reading ECR repository URLs from Terraform..."
AGENT_REPO=$(get_tf_output "ecr_agent_repository_url") || error "Could not read ecr_agent_repository_url. Run terraform apply first."
APP_REPO=$(get_tf_output "ecr_app_repository_url") || error "Could not read ecr_app_repository_url. Run terraform apply first."
ECS_CLUSTER=$(get_tf_output "ecs_cluster_name") || error "Could not read ecs_cluster_name."

# Derive service name from Terraform project_name
SERVICE_NAME=$(get_tf_output "ecs_service_name" 2>/dev/null || echo "")
if [[ -z "$SERVICE_NAME" ]]; then
    # Fallback: construct from cluster name pattern
    PROJECT_NAME=$(echo "$ECS_CLUSTER" | sed 's/-cluster$//')
    SERVICE_NAME="${PROJECT_NAME}-app"
    warn "Could not read ecs_service_name output; using: $SERVICE_NAME"
fi

# Extract AWS account ID and region from repo URL
AWS_ACCOUNT_ID=$(echo "$AGENT_REPO" | cut -d. -f1)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
log "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Resolve Dockerfile paths
AGENT_DOCKERFILE="${AGENT_DOCKERFILE:-${APP_DIR}/strands_agents/Dockerfile}"
AGENT_CONTEXT="${AGENT_CONTEXT:-${APP_DIR}/strands_agents}"
APP_DOCKERFILE="${APP_DOCKERFILE:-${APP_DIR}/Dockerfile}"
APP_CONTEXT="${APP_CONTEXT:-${APP_DIR}}"

# Build and push agent image
if [[ "$TARGET" == "all" || "$TARGET" == "agent" ]]; then
    log ""
    log "${BOLD}Building agent image...${NC}"
    docker build \
        -t "${AGENT_REPO}:${IMAGE_TAG}" \
        -f "$AGENT_DOCKERFILE" \
        "$AGENT_CONTEXT"

    log "Pushing agent image..."
    docker push "${AGENT_REPO}:${IMAGE_TAG}"
    success "Agent image pushed: ${AGENT_REPO}:${IMAGE_TAG}"
fi

# Build and push app image
if [[ "$TARGET" == "all" || "$TARGET" == "app" ]]; then
    log ""
    log "${BOLD}Building app image...${NC}"
    docker build \
        -t "${APP_REPO}:${IMAGE_TAG}" \
        -f "$APP_DOCKERFILE" \
        "$APP_CONTEXT"

    log "Pushing app image..."
    docker push "${APP_REPO}:${IMAGE_TAG}"
    success "App image pushed: ${APP_REPO}:${IMAGE_TAG}"
fi

# Force ECS redeployment
log ""
log "Forcing ECS service redeployment..."
aws ecs update-service \
    --cluster "$ECS_CLUSTER" \
    --service "$SERVICE_NAME" \
    --force-new-deployment \
    --region "$AWS_REGION" \
    --no-cli-pager > /dev/null

success ""
success "============================================="
success " Deployment initiated!"
success "============================================="
success ""
success " Images pushed:"
if [[ "$TARGET" == "all" || "$TARGET" == "agent" ]]; then
    success "   Agent: ${AGENT_REPO}:${IMAGE_TAG}"
fi
if [[ "$TARGET" == "all" || "$TARGET" == "app" ]]; then
    success "   App:   ${APP_REPO}:${IMAGE_TAG}"
fi
success ""
success " ECS service redeployment triggered."
success " Monitor progress:"
success "   aws ecs describe-services --cluster $ECS_CLUSTER --services $SERVICE_NAME --query 'services[0].deployments' --no-cli-pager"
success ""
