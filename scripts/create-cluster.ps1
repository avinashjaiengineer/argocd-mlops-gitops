<#
.SYNOPSIS
  Creates the EKS cluster and the ECR repository for the GitOps ML platform.

.NOTES
  Costs money while running (EKS control plane + 2x m7i-flex.large + NAT gateway,
  roughly USD 0.35/hour). Tear down with:
    eksctl delete cluster --name argocd-mlops --region us-east-1
#>
param(
    [string]$ClusterName = "argocd-mlops",
    [string]$Region = "us-east-1",
    # m7i-flex.large is free-tier eligible. Accounts on the AWS Free plan cannot
    # launch t3.medium: the node group then hangs in CREATING, and CloudTrail
    # shows RunInstances failing with "instance type is not eligible for Free Tier".
    [string]$NodeType = "m7i-flex.large",
    [string]$EcrRepository = "argocd-ml-api"
)

# Not "Stop": in Windows PowerShell 5.1 that turns any stderr output from
# native tools (eksctl/aws "not found" checks) into a terminating error.
# Failures are detected through $LASTEXITCODE instead.
$ErrorActionPreference = "Continue"

foreach ($tool in "aws", "eksctl", "kubectl") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not installed or not on PATH."
    }
}

$AccountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "AWS credentials not configured. Run 'aws configure'." }
Write-Host "AWS account: $AccountId"

# --- EKS cluster ---
$existing = eksctl get cluster --name $ClusterName --region $Region 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Cluster '$ClusterName' already exists, skipping creation."
} else {
    # --with-oidc is needed later for IRSA (AWS Load Balancer Controller, External Secrets).
    eksctl create cluster `
        --name $ClusterName `
        --region $Region `
        --nodegroup-name workers `
        --node-type $NodeType `
        --nodes 2 `
        --nodes-min 1 `
        --nodes-max 3 `
        --managed `
        --with-oidc
    if ($LASTEXITCODE -ne 0) { throw "eksctl create cluster failed." }
}

aws eks update-kubeconfig --name $ClusterName --region $Region | Out-Null
kubectl get nodes

# --- ECR repository ---
aws ecr describe-repositories --repository-names $EcrRepository --region $Region 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "ECR repository '$EcrRepository' already exists."
} else {
    aws ecr create-repository `
        --repository-name $EcrRepository `
        --image-scanning-configuration scanOnPush=true `
        --region $Region | Out-Null
    Write-Host "Created ECR repository '$EcrRepository'."
}

$EcrUri = "$AccountId.dkr.ecr.$Region.amazonaws.com/$EcrRepository"
Write-Host ""
Write-Host "ECR URI: $EcrUri"
Write-Host "Next: replace ACCOUNT_ID in k8s/deployment.yaml with $AccountId"
