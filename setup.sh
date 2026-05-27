#!/usr/bin/env bash
# Algoverse AWS Bootstrap — one-command setup
# Usage: curl -fsSL https://raw.githubusercontent.com/algoverse/algoverse-aws/main/setup.sh | bash
#
# What this does:
#   1. Checks / installs AWS CLI
#   2. Walks you through account credentials
#   3. Creates S3 bucket, IAM role, budget alerts
#   4. Requests GPU quota
#   5. Writes .sagemaker.env and prints a summary card
#
# Requirements: bash 4+, python3, curl. macOS and Linux supported.
# Windows: run inside WSL2.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────── #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}▸ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}"; exit 1; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Globals (set during setup) ────────────────────────────────────────────── #
AWS_REGION="${AWS_REGION:-us-east-2}"
HANDLE=""
BUCKET=""
ROLE_ARN=""
INSTANCE_TYPE=""

# ── Step 0: Platform check ────────────────────────────────────────────────── #
header "Algoverse AWS Bootstrap"
echo "This script takes about 20 minutes on a fresh AWS account."
echo "Press Ctrl-C at any time to cancel."
echo ""

if [[ "${OSTYPE}" == "msys"* ]] || [[ "${OSTYPE}" == "cygwin"* ]]; then
    error "Windows detected. Run this inside WSL2: wsl --install (from Admin PowerShell), then reopen as Ubuntu."
fi

# ── Step 1: AWS CLI ───────────────────────────────────────────────────────── #
header "Step 1/6 — AWS CLI"
if ! command -v aws &>/dev/null; then
    warn "AWS CLI not found. Installing..."
    if [[ "${OSTYPE}" == "darwin"* ]]; then
        if command -v brew &>/dev/null; then
            brew install awscli
        else
            curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/awscliv2.pkg
            sudo installer -pkg /tmp/awscliv2.pkg -target /
        fi
    else
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
        unzip -q /tmp/awscliv2.zip -d /tmp/
        sudo /tmp/aws/install
    fi
fi
AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
success "AWS CLI ${AWS_VERSION}"

# ── Step 2: Credentials ───────────────────────────────────────────────────── #
header "Step 2/6 — AWS credentials"
echo ""
echo "You need an AWS Access Key ID and Secret Access Key."
echo "Get them from: AWS Console → IAM → Users → Your user → Security credentials → Create access key"
echo ""

if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    success "Already authenticated (account ${ACCOUNT_ID})"
else
    warn "Not authenticated. Running aws configure..."
    aws configure
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    success "Authenticated (account ${ACCOUNT_ID})"
fi

# ── Step 3: Participant details ───────────────────────────────────────────── #
header "Step 3/6 — Your details"
echo ""
echo -n "Your handle/username (e.g. edward, jane-doe): "
read -r HANDLE
HANDLE="${HANDLE:-participant}"
HANDLE="${HANDLE//[^a-zA-Z0-9-]/-}"  # sanitize

echo ""
echo "Which GPU instance do you need?"
echo "  1) ml.g6.xlarge   — 1× L4,   24GB, ~\$1.10/hr  (1–7B models, most projects)"
echo "  2) ml.g5.4xlarge  — 1× A10G, 24GB, ~\$1.62/hr  (pretraining, EEG, vision)"
echo "  3) ml.g6.12xlarge — 4× L4,   96GB, ~\$5.67/hr  (13–34B models)"
echo "  4) ml.g6e.xlarge  — 1× L40S, 48GB, ~\$1.86/hr  (larger models, Studio only)"
echo ""
echo -n "Pick 1-4 [default: 1]: "
read -r INSTANCE_CHOICE
case "${INSTANCE_CHOICE:-1}" in
    1) INSTANCE_TYPE="ml.g6.xlarge"   ;;
    2) INSTANCE_TYPE="ml.g5.4xlarge"  ;;
    3) INSTANCE_TYPE="ml.g6.12xlarge" ;;
    4) INSTANCE_TYPE="ml.g6e.xlarge"  ;;
    *) INSTANCE_TYPE="ml.g6.xlarge"   ;;
esac
success "Instance: ${INSTANCE_TYPE}"

# ── Step 4: Budget alerts ─────────────────────────────────────────────────── #
header "Step 4/6 — Budget alerts"
info "Creating budget with alerts at \$50, \$100, \$150..."

EMAIL=$(aws iam get-user --query 'User.Tags[?Key==`email`].Value' --output text 2>/dev/null || true)
if [[ -z "${EMAIL}" ]]; then
    echo -n "Your email for budget alerts: "
    read -r EMAIL
fi

# Create budget (idempotent — fails silently if exists)
aws budgets create-budget \
    --account-id "${ACCOUNT_ID}" \
    --budget "{
        \"BudgetName\": \"algoverse-${HANDLE}-total\",
        \"BudgetLimit\": {\"Amount\": \"200\", \"Unit\": \"USD\"},
        \"TimeUnit\": \"MONTHLY\",
        \"BudgetType\": \"COST\"
    }" \
    --notifications-with-subscribers "[
        {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":25,\"ThresholdType\":\"PERCENTAGE\"},
         \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${EMAIL}\"}]},
        {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":50,\"ThresholdType\":\"PERCENTAGE\"},
         \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${EMAIL}\"}]},
        {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":75,\"ThresholdType\":\"PERCENTAGE\"},
         \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${EMAIL}\"}]}
    ]" 2>/dev/null && success "Budget alerts created" || warn "Budget may already exist — skipping"

# ── Step 5: S3 bucket + IAM role ─────────────────────────────────────────── #
header "Step 5/6 — S3 bucket + IAM role"

BUCKET="algoverse-${HANDLE}-${ACCOUNT_ID:0:8}-${AWS_REGION}"
info "Creating S3 bucket: ${BUCKET}"

if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" 2>/dev/null \
        && success "Bucket created" || warn "Bucket may already exist"
else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>/dev/null \
        && success "Bucket created" || warn "Bucket may already exist"
fi

# Enable versioning (cheap protection against accidental deletes)
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled 2>/dev/null || true

# Create IAM role for SageMaker
ROLE_NAME="AmazonSageMaker-${HANDLE}"
info "Creating IAM role: ${ROLE_NAME}"

TRUST_POLICY='{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "sagemaker.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}'

aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "SageMaker execution role for Algoverse participant ${HANDLE}" \
    2>/dev/null && success "IAM role created" || warn "Role may already exist"

# Attach managed policies
aws iam attach-role-policy --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null || true
aws iam attach-role-policy --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
success "Role ARN: ${ROLE_ARN}"

# ── Step 6: Quota request ─────────────────────────────────────────────────── #
header "Step 6/6 — GPU quota"

# Map instance to quota service code
case "${INSTANCE_TYPE}" in
    ml.g6.xlarge)   QUOTA_CODE="L-1194D77F" QUOTA_NAME="ml.g6.xlarge for training job usage" ;;
    ml.g5.4xlarge)  QUOTA_CODE="L-B5D1601B" QUOTA_NAME="ml.g5.4xlarge for training job usage" ;;
    ml.g6.12xlarge) QUOTA_CODE="L-62F9E6DE" QUOTA_NAME="ml.g6.12xlarge for training job usage" ;;
    ml.g6e.xlarge)  QUOTA_CODE="L-E31B2B4A" QUOTA_NAME="ml.g6e.xlarge for training job usage" ;;
    *)              QUOTA_CODE="" ;;
esac

CURRENT_QUOTA=0
if [[ -n "${QUOTA_CODE}" ]]; then
    CURRENT_QUOTA=$(aws service-quotas get-service-quota \
        --service-code sagemaker \
        --quota-code "${QUOTA_CODE}" \
        --region "${AWS_REGION}" \
        --query 'Quota.Value' --output text 2>/dev/null || echo 0)
fi

if awk "BEGIN{exit !(${CURRENT_QUOTA} >= 1)}" 2>/dev/null; then
    success "Quota already approved: ${INSTANCE_TYPE} = ${CURRENT_QUOTA}"
else
    warn "Quota for ${INSTANCE_TYPE} is 0. Requesting increase to 1..."
    aws service-quotas request-service-quota-increase \
        --service-code sagemaker \
        --quota-code "${QUOTA_CODE}" \
        --desired-value 1 \
        --region "${AWS_REGION}" 2>/dev/null \
        && warn "Quota request submitted — AWS typically responds in 24–72h. You'll get an email." \
        || warn "Quota request failed (may already be pending). Check AWS Service Quotas console."
fi

# ── Write .sagemaker.env ──────────────────────────────────────────────────── #
ENV_FILE="${HOME}/.sagemaker.env"
if [[ -f "${ENV_FILE}" ]]; then
    warn ".sagemaker.env already exists — not overwriting. Check ${ENV_FILE}"
else
    cat > "${ENV_FILE}" <<EOF
# Algoverse SageMaker environment — generated $(date)
AWS_REGION=${AWS_REGION}
S3_BUCKET=${BUCKET}
SM_ROLE_ARN=${ROLE_ARN}
STUDENT_HANDLE=${HANDLE}
INSTANCE_TYPE=${INSTANCE_TYPE}
PROJECT_SLUG=my-project
HF_TOKEN=
EOF
    chmod 600 "${ENV_FILE}"
    success "Wrote ${ENV_FILE}"
fi

# ── Summary card ──────────────────────────────────────────────────────────── #
echo ""
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Setup complete${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "  Account:   ${ACCOUNT_ID}"
echo -e "  Region:    ${AWS_REGION}"
echo -e "  Bucket:    ${BUCKET}"
echo -e "  Role:      ${ROLE_NAME}"
echo -e "  Instance:  ${INSTANCE_TYPE}"
echo ""
echo -e "${YELLOW}Next steps:${RESET}"
echo "  1. Edit ~/.sagemaker.env — add HF_TOKEN and PROJECT_SLUG"
echo "  2. Copy templates/sagemaker_submit.py into your project"
echo "  3. Run: python sagemaker_submit.py --dry-run"
if awk "BEGIN{exit !(${CURRENT_QUOTA} < 1)}" 2>/dev/null; then
    echo ""
    echo -e "  ${YELLOW}⚠ GPU quota pending AWS approval (24–72h).${RESET}"
    echo "    You can prepare everything else while you wait."
fi
echo ""
echo "  Full docs: https://github.com/algoverse/algoverse-aws"
echo -e "${BOLD}════════════════════════════════════════${RESET}"
