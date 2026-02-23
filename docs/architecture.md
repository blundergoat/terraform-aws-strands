# Architecture

Reference for AI coding agents. Read this before modifying any module.

## System Overview

```mermaid
graph TB
    User([User]) --> R53[Route53 DNS]
    R53 --> ALB[ALB - HTTPS]
    ALB --> WAF[WAF - OWASP + Rate Limit]
    WAF --> ALB
    subgraph Public Subnets
        ALB
    end
    subgraph Private Subnets
        subgraph ECS Fargate Task
            App[App :8080 - Web UI]
            Agent[Agent :8000 - FastAPI]
            Mercure[Mercure :3701 - SSE Hub]
        end
    end
    ALB -- "default path" --> App
    ALB -- "/.well-known/mercure*" --> Mercure
    App -- "localhost:8000" --> Agent
    Agent --> Bedrock[AWS Bedrock - LLM]
    Agent --> DDB[(DynamoDB - Sessions)]
    Agent --> SM[Secrets Manager]
    subgraph Supporting Services
        ECR[ECR - agent + app images]
        CW[CloudWatch Logs + Alarms]
        SNS[SNS Notifications]
        ACM[ACM Certificate]
    end
    CW --> SNS
    Agent -.-> CW
    App -.-> CW
```

The three containers share a network namespace so App calls Agent over localhost -- no service discovery needed. ALB sits in public subnets while ECS tasks run in private subnets, keeping workloads off the public internet. WAF attaches to the ALB to filter traffic before it reaches any container.

## Request Flow

```mermaid
sequenceDiagram
    participant U as User
    participant R as Route53
    participant A as ALB (HTTPS)
    participant W as WAF
    participant App as App :8080
    participant Ag as Agent :8000
    participant M as Mercure :3701
    participant B as Bedrock
    participant D as DynamoDB
    U->>R: DNS lookup (subdomain.hosted_zone)
    R->>A: Resolve to ALB
    A->>W: Inspect request
    W->>A: Allow/Block
    alt Default path
        A->>App: Forward to :8080
        App->>Ag: localhost:8000 API call
        Ag->>B: LLM inference
        B-->>Ag: Response stream
        Ag->>D: Persist session
        Ag-->>App: Return result
        App-->>U: Render response
    else /.well-known/mercure*
        A->>M: Forward to :3701
        M-->>U: SSE stream
    end
```

HTTP hits the ALB (which redirects to HTTPS), WAF evaluates OWASP rules and rate limits, then path routing splits traffic. App handles the UI and proxies to Agent over localhost; Mercure handles SSE streaming on its dedicated path. Agent reads its API key from Secrets Manager and writes sessions to DynamoDB.

## Deployment Flow

```mermaid
flowchart LR
    subgraph One-Time Bootstrap
        B1[bootstrap.sh] --> S3[S3 State Bucket]
        B1 --> DL[DynamoDB Lock Table]
    end
    subgraph Infrastructure
        TF[terraform apply] --> Infra[All AWS Resources]
    end
    subgraph Application Deploy
        DS[deploy.sh] --> Build[Docker Build]
        Build --> Push[Push to ECR]
        Push --> Roll[ECS Rolling Deploy]
    end
    S3 -.-> TF
    DL -.-> TF
    Infra -.-> DS
    subgraph Optional CI/CD
        GH[GitHub Actions] --> OIDC[OIDC Role]
        OIDC --> DS
    end
```

Bootstrap runs once to create the Terraform state backend. `terraform apply` provisions all infrastructure. Application deploys are decoupled -- `deploy.sh` builds images, pushes to ECR, and triggers a rolling ECS deployment without re-running Terraform.

## Module Dependency Graph

```mermaid
flowchart TB
    subgraph "Phase 1 - Independent"
        dynamodb
        ecr_agent[ecr - agent]
        ecr_app[ecr - app]
        observability
        secrets
    end
    subgraph "Phase 2"
        security
    end
    subgraph "Phase 3"
        ecs
        dns
    end
    subgraph "Phase 4"
        alb
    end
    subgraph "Phase 5"
        ecs_service
        waf
    end
    subgraph "Phase 6"
        alarms
    end
    iam[iam - spans phases 1-5]
    security --> |sg| alb
    security --> |sg| ecs_service
    dns --> |acm cert| alb
    iam --> |task roles| ecs
    observability --> |log group| ecs
    ecr_agent --> |repo url| ecs
    ecr_app --> |repo url| ecs
    ecs --> |task def| ecs_service
    alb --> |target groups| ecs_service
    alb --> |alb arn| waf
    alb --> |alb arn| alarms
    ecs --> |service name| alarms
    dynamodb --> |table| iam
    secrets --> |arns| iam
```

Phase 1 modules have no dependencies and deploy in parallel. Security must exist before ALB and ECS service because both need security group references. ALB cannot be created until DNS provides the ACM certificate. IAM spans multiple phases: task roles are needed at Phase 3 for ECS task definitions, but the OIDC policy references outputs from Phase 3-5 resources.
