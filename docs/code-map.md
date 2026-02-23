# Code Map

Quick-reference tree map for the `terraform-aws-strands` repository.

Deploys a [Strands Agents](https://github.com/strands-agents/sdk-python) application on **AWS ECS Fargate** with three sidecar containers (Agent on port 8000, App on port 8080, Mercure SSE hub on port 3701) behind an ALB with WAF, Route53 DNS, and ACM HTTPS.

**Stack:** Terraform >= 1.5.0, AWS provider 5.x-6.x, Bash, Docker. Default region: us-east-1.

```
terraform-aws-strands/
├── .claude/                          = Claude Code local settings (gitignored)
├── .gitignore                        = Ignores .terraform/, *.tfstate, *.tfvars, backend.hcl, IDE files
├── AGENTS.md                         = Shared coding-agent instructions (style, PR guidelines, commands)
├── CLAUDE.md                         = Claude Code project context and conventions
├── GEMINI.md                         = Gemini CLI project context and mandates
├── LICENSE                           = MIT license
├── README.md                         = Architecture overview, quick start, VPC/DNS setup guide
│
├── scripts/
│   ├── deploy.sh                     = Build Docker images, push to ECR, force ECS redeployment
│   ├── preflight-checks.sh           = Run terraform fmt -check + terraform validate on all modules
│   └── terraform.sh                  = Terraform wrapper: handles AWS profile/region, backend.hcl, bootstrap mode
│
├── terraform/
│   ├── bootstrap/                    = One-time setup: S3 state bucket + DynamoDB lock table (LOCAL state -- never delete tfstate)
│   │   ├── main.tf                   = KMS key, S3 bucket (versioned, encrypted, private), DynamoDB locks table
│   │   ├── variables.tf              = bucket name, lock table name, region, project, environment
│   │   ├── outputs.tf                = state_bucket_name, lock_table_name (paste into backend.hcl)
│   │   ├── versions.tf               = Terraform + AWS provider version constraints
│   │   └── .terraform.lock.hcl       = GENERATED -- provider dependency lock, do not edit
│   │
│   ├── environments/
│   │   └── main/                     = Root orchestration module -- wires all modules together in 6 phases
│   │       ├── main.tf               = Provider config, VPC lookup, secret generation, all module calls, Route53 records
│   │       ├── variables.tf          = All configurable inputs (VPC, DNS, agent model, WAF, CI/CD, etc.)
│   │       ├── outputs.tf            = ECR URLs, ECS cluster/service names, app URL, GitHub OIDC role ARN
│   │       ├── backend.tf            = S3 backend declaration (values come from backend.hcl)
│   │       ├── versions.tf           = Terraform >= 1.5.0, AWS provider 5.x-6.x, random provider 3.x
│   │       ├── backend.hcl.example   = Template for backend config -- copy to backend.hcl (gitignored)
│   │       ├── staging.tfvars.example    = Template for dev environment variables
│   │       ├── production.tfvars.example = Template for prod environment variables
│   │       └── .terraform.lock.hcl   = GENERATED -- provider dependency lock, do not edit
│   │
│   └── modules/                      = 12 reusable Terraform modules (each has main.tf, variables.tf, outputs.tf)
│       │
│       ├── alarms/                   = CloudWatch alarms (ALB 5xx, p95 latency, ECS running tasks) + SNS topic with KMS
│       ├── alb/                      = Application Load Balancer, HTTPS listener (TLS 1.3), HTTP->HTTPS redirect, Mercure path rule on port 3701
│       ├── dns/                      = Route53 hosted zone (optional create), ACM certificate with DNS validation
│       ├── dynamodb/                 = DynamoDB sessions table (on-demand billing, TTL-enabled, keyed by session_id)
│       ├── ecr/                      = ECR repository with scan-on-push, lifecycle policy (keep 10 images), AES-256 encryption
│       ├── ecs/                      = ECS Fargate cluster + task definition (agent + app + Mercure containers, 1 vCPU / 2 GB)
│       ├── ecs-service/              = ECS service with circuit-breaker rollback, dual target group registration, autoscaling (CPU 50% / memory 60%)
│       ├── iam/                      = Task execution role, task role (Bedrock, DynamoDB, Secrets Manager), GitHub Actions OIDC role (optional)
│       ├── observability/            = CloudWatch log groups for agent, app, and Mercure containers
│       ├── secrets/                  = AWS Secrets Manager secrets (api-key, app-secret, mercure-jwt-secret) via for_each
│       ├── security/                 = Security groups: ALB (HTTP/HTTPS in, app port out) + ECS (ALB-only ingress, CIDR egress)
│       └── waf/                      = WAFv2 Web ACL: Common Rules, Known Bad Inputs, SQLi, IP Reputation, rate limiting, optional anonymous IP blocking
│
└── docs/
    └── code-map.md                   = This file
```

## Module Dependency Phases

```
Phase 1 (independent):  dynamodb, ecr (x2), observability, secrets
Phase 2:                security (needs vpc_id), iam (spans phases 2-5)
Phase 3:                ecs (needs iam roles, observability, ecr), dns
Phase 4:                alb (needs security, dns cert, vpc/subnets)
Phase 5:                ecs-service (needs ecs, alb, security), waf (needs alb)
Phase 6:                alarms (needs alb, ecs)
```

## Generated / Never-Edit Files

| Path | Notes |
|---|---|
| `**/.terraform/` | Provider binaries and cached modules. Gitignored. Recreated by `terraform init`. |
| `**/.terraform.lock.hcl` | Provider dependency lock files. GENERATED by `terraform init`. Commit but do not hand-edit. |
| `*.tfstate` / `*.tfstate.backup` | Terraform state. Gitignored. Stored in S3 after bootstrap. |
| `backend.hcl` | User-specific backend config. Gitignored. Copy from `backend.hcl.example`. |
| `*.tfvars` (non-example) | User-specific variable values. Gitignored. Copy from `*.tfvars.example`. |

## Key Ports

| Port | Container | Role |
|---|---|---|
| 8000 | Agent (Python FastAPI) | Internal sidecar, calls Bedrock |
| 8080 | App (Web UI) | ALB default target |
| 3701 | Mercure (SSE hub) | ALB path-routed at `/.well-known/mercure*` |
