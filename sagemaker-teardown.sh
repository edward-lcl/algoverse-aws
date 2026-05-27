#!/bin/bash
# SageMaker teardown — removes everything sagemaker-bootstrap.md created.
# Idempotent. Missing resources are skipped.
# Handles BOTH new naming (no cohort prefix) AND legacy "cohort-*" names from earlier runs.
#
# Usage: bash sagemaker-teardown.sh
# Requires: ~/.sagemaker.env (or legacy ~/.cohort-sagemaker.env) to exist.

set -u

if [ -f ~/.sagemaker.env ]; then
  ENV_FILE=~/.sagemaker.env
elif [ -f ~/.cohort-sagemaker.env ]; then
  ENV_FILE=~/.cohort-sagemaker.env
  echo "Using legacy env ~/.cohort-sagemaker.env (consider migrating to ~/.sagemaker.env)"
else
  echo "No env file found at ~/.sagemaker.env or ~/.cohort-sagemaker.env. Nothing to tear down."
  exit 0
fi

set -a; source "$ENV_FILE"; set +a

: "${STUDENT_HANDLE:?STUDENT_HANDLE missing in env file}"
: "${AWS_REGION:?AWS_REGION missing in env file}"
: "${AWS_PROFILE:=default}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")

# Each resource has a new name and a legacy name — try both.
NOTEBOOK_NAMES=("${STUDENT_HANDLE}-notebook" "cohort-${STUDENT_HANDLE}")
ROLE_NAMES=("AmazonSageMaker-${STUDENT_HANDLE}" "AmazonSageMaker-Cohort-${STUDENT_HANDLE}")
BUDGET_NAMES=("${STUDENT_HANDLE}-sagemaker-credit-burn" "cohort-${STUDENT_HANDLE}-credit-burn")
LIFECYCLE_NAMES=("sagemaker-idle-shutdown" "cohort-idle-shutdown")
BUCKET_NAMES=("${STUDENT_HANDLE}-${ACCOUNT_ID:0:6}-${AWS_REGION}" "cohort-${STUDENT_HANDLE}-${ACCOUNT_ID:0:6}-${AWS_REGION}")

echo "Tearing down SageMaker setup for: $STUDENT_HANDLE"
echo "  Account: $ACCOUNT_ID, Region: $AWS_REGION"
echo

# 1. Notebooks
for NB in "${NOTEBOOK_NAMES[@]}"; do
  if aws sagemaker describe-notebook-instance --notebook-instance-name "$NB" --region "$AWS_REGION" >/dev/null 2>&1; then
    STATUS=$(aws sagemaker describe-notebook-instance --notebook-instance-name "$NB" --region "$AWS_REGION" --query 'NotebookInstanceStatus' --output text)
    if [ "$STATUS" = "InService" ] || [ "$STATUS" = "Pending" ] || [ "$STATUS" = "Updating" ]; then
      echo "Stopping notebook $NB..."
      aws sagemaker stop-notebook-instance --notebook-instance-name "$NB" --region "$AWS_REGION"
      aws sagemaker wait notebook-instance-stopped --notebook-instance-name "$NB" --region "$AWS_REGION"
    fi
    if [ "$STATUS" != "Deleting" ]; then
      aws sagemaker delete-notebook-instance --notebook-instance-name "$NB" --region "$AWS_REGION"
      echo "Notebook $NB deleted"
    fi
  fi
done

# 2. Lifecycle configs
for LC in "${LIFECYCLE_NAMES[@]}"; do
  if aws sagemaker describe-notebook-instance-lifecycle-config --notebook-instance-lifecycle-config-name "$LC" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws sagemaker delete-notebook-instance-lifecycle-config --notebook-instance-lifecycle-config-name "$LC" --region "$AWS_REGION" 2>/dev/null \
      && echo "Lifecycle config $LC deleted" \
      || echo "Lifecycle config $LC: in use elsewhere, skipping"
  fi
done

# 3. IAM roles
for ROLE in "${ROLE_NAMES[@]}"; do
  if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null || true
    for p in $(aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames' --output text); do
      aws iam delete-role-policy --role-name "$ROLE" --policy-name "$p"
    done
    aws iam delete-role --role-name "$ROLE"
    echo "IAM role $ROLE deleted"
  fi
done

# 4. S3 buckets — explicit S3_BUCKET from env first, then known patterns
TRIED_BUCKETS=()
for B in "${S3_BUCKET:-}" "${BUCKET_NAMES[@]}"; do
  [ -z "$B" ] && continue
  [[ " ${TRIED_BUCKETS[*]} " == *" $B "* ]] && continue
  TRIED_BUCKETS+=("$B")
  if aws s3api head-bucket --bucket "$B" 2>/dev/null; then
    echo "Emptying + deleting S3 bucket $B..."
    aws s3 rm "s3://$B" --recursive >/dev/null
    aws s3api delete-bucket --bucket "$B" --region "$AWS_REGION"
    echo "S3 bucket $B deleted"
  fi
done

# 5. Budgets
for B in "${BUDGET_NAMES[@]}"; do
  if aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$B" >/dev/null 2>&1; then
    aws budgets delete-budget --account-id "$ACCOUNT_ID" --budget-name "$B"
    echo "Budget $B deleted"
  fi
done

echo
echo "Teardown complete."
echo "Service Quota requests are NOT deleted (free, AWS keeps the approved limits)."
echo "For a fully fresh state: rm $ENV_FILE"
