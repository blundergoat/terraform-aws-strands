# terraform-aws-strands

AWS infrastructure for deploying a [Strands Agents](https://github.com/strands-agents/sdk-python) application on ECS Fargate with Mercure real-time streaming.

Supports dual-environment workflows (staging/production), VPC tag lookups, and remote state backends.

## What This Deploys

- **ECS Fargate** cluster with up to 3 sidecar containers (agent, app, Mercure) and autoscaling
- **Application Load Balancer** with HTTPS termination, path-based routing for Mercure SSE
- **ECR** repositories for agent and app Docker images
- **DynamoDB** table for session persistence with TTL
- **WAF** with AWS managed rule sets and rate limiting
- **Route53** DNS with ACM certificate (auto-validated)
- **CloudWatch** log groups and alarms with SNS notifications
- **IAM** roles for ECS tasks (Bedrock, DynamoDB, Secrets Manager access)
- **Secrets Manager** for API key storage
- **GitHub Actions OIDC** role for CI/CD (optional)

## Prerequisites

1. **AWS CLI** configured with appropriate profiles for your staging and production accounts
2. **Terraform** >= 1.5.0
3. **Docker** for building and pushing images
4. **A VPC** with public and private subnets (looked up by tag name or passed as IDs)
5. **A Route53 hosted zone** for your domain (or set `create_hosted_zone = true`)
6. **AWS Bedrock access** enabled in your region

## Quick Start

### 1. Configure backend

```bash
cd terraform/environments/main

# Use the shared state bucket (recommended)
cp backend.hcl.example backend.hcl
# Edit backend.hcl -- configure your S3 state bucket
```

### 2. Create environment tfvars

```bash
# Staging
cp staging.tfvars.example staging.tfvars
# Edit staging.tfvars -- fill in vpc_name, hosted_zone, hosted_zone_id, project_name

# Production
cp production.tfvars.example production.tfvars
# Edit production.tfvars -- same fields, production values
```

### 3. Deploy infrastructure

```bash
# Initialize
./scripts/terraform.sh init

# Plan staging
./scripts/terraform.sh plan -var-file=staging.tfvars

# Apply staging
./scripts/terraform.sh apply -var-file=staging.tfvars

# Plan production
AWS_PROFILE=prod ./scripts/terraform.sh plan -var-file=production.tfvars
```

### 4. Build and push images

```bash
# Deploy staging
APP_DIR=/path/to/your/app ./scripts/deploy.sh

# Deploy production
AWS_PROFILE=prod APP_DIR=/path/to/your/app ./scripts/deploy.sh
```

## Environment Detection

Environment is determined by the `environment` variable in your tfvars:

| Environment | Behaviour |
|---|---|
| `dev` | ALB deletion protection off, APP_DEBUG=1, autoscaling disabled |
| `prod` | ALB deletion protection on, APP_DEBUG=0, autoscaling enabled |

## VPC Lookup

Two options for specifying your VPC and subnets:

**Option A: Tag name lookup** (recommended)
```hcl
vpc_name                   = "My VPC"
public_subnet_tag_pattern  = "*Public*"
private_subnet_tag_pattern = "*Private*"
```

**Option B: Explicit IDs**
```hcl
vpc_id             = "vpc-xxxxxxxxx"
public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
private_subnet_ids = ["subnet-ccc", "subnet-ddd"]
```

## Architecture

```
Route 53 (<subdomain>.<hosted_zone>)
     |
     v
Application Load Balancer (public subnets)
     |--- /.well-known/mercure*  ---> Mercure target group (port 3701)
     |--- default                ---> App target group (port 8080)
     |
     v
ECS Fargate Task (private subnets)
  - App container (port 8080)           <-- ALB default target
  - Agent container (port 8000)         <-- internal sidecar
  - Mercure container (port 3701)       <-- ALB path-routed
       |
       +-- AWS Bedrock (model invocation)
       +-- DynamoDB (session persistence)
```

All three containers run in the same ECS task (shared network namespace), so they communicate via `localhost`.

## Module Dependency Graph

```
Phase 1 (independent):  dynamodb, ecr, ecr_app, observability, secrets
Phase 2:                security (needs vpc_id)
Phase 3:                ecs (needs iam task roles, observability, ecr), dns (needs hosted_zone_id)
Phase 4:                alb (needs security, dns cert, vpc/subnets)
Phase 5:                ecs_service (needs ecs, alb, security), waf (needs alb)
Phase 6:                alarms (needs alb, ecs)
```

> **Note:** The IAM module spans multiple phases. Task execution and task roles are created early (needed by ECS in phase 3), but the GitHub OIDC deploy policy references phase 3-5 outputs (ECS cluster/service ARNs, ALB target group). Terraform handles this via implicit dependency resolution.

## Terraform Outputs

| Output | Description |
|---|---|
| `ecr_agent_repository_url` | ECR URL for pushing agent Docker images |
| `ecr_app_repository_url` | ECR URL for pushing app Docker images |
| `ecs_cluster_name` | ECS cluster name (for `deploy.sh`) |
| `ecs_service_name` | ECS service name (for `deploy.sh`) |
| `alb_dns_name` | ALB DNS name (test before DNS propagates) |
| `app_url` | Full application URL |
| `api_key_secret_name` | Secrets Manager path for the API key |
| `github_actions_role_arn` | IAM role ARN for GitHub Actions OIDC |

## Scripts

| Script | Description |
|---|---|
| `scripts/terraform.sh` | Terraform wrapper with profile/region defaults, bootstrap support |
| `scripts/deploy.sh` | Build Docker images, push to ECR, trigger ECS redeployment |

Both scripts read `AWS_PROFILE` and `AWS_REGION` from environment variables (default region: `us-east-1`).

## License

MIT
