# Algoverse AWS Bootstrap — Claude Code Agent

**For you (the participant):** clone this repo inside your project as `.algoverse/`, then open an agent session in the project root. The agent reads `.algoverse/AGENTS.md` and handles setup end-to-end. Have your AWS credentials ready only if the scan says cloud setup is needed.

**For you (the agent):** two stages. Stage 1 — scan the project, local hardware, and likely experiment type; recommend local/API/SageMaker path; stop. Stage 2 (on `proceed`) — provision what is actually needed and print a summary card.

---

## Stage 1 — Scan and brief

Run these silently, then surface only the findings:

```bash
uname -s
python .algoverse/scripts/local_compute_check.py 2>/dev/null || python scripts/local_compute_check.py 2>/dev/null || true
which aws >/dev/null 2>&1 && aws --version || echo "aws_cli=missing"
aws sts get-caller-identity 2>/dev/null && echo "aws_auth=ok" || echo "aws_auth=missing"
test -f ~/.sagemaker.env && cat ~/.sagemaker.env || echo "env=missing"
ls -la
test -f README.md && head -100 README.md
for f in $(find . -maxdepth 1 -name "*.md" ! -name "README.md" ! -name "AGENTS.md" 2>/dev/null | head -8); do
  echo "=== $f ===" && head -50 "$f"
done
test -f pyproject.toml && cat pyproject.toml
test -f requirements.txt && head -30 requirements.txt
find . -maxdepth 3 \( -name "train*.py" -o -name "finetune*.py" -o -name "run_*.py" -o -name "main.py" -o -name "*submit*.py" \) ! -path "*/.git/*" ! -path "*/.venv/*" 2>/dev/null | head -8
```

Infer workload from findings. Present a compute recommendation with a cost/fit note. If the repo is empty, ask what they're building before continuing.

First choose the compute route:
- Local compute if a team machine has enough RAM/VRAM for pilots, preprocessing, local inference, or small fine-tunes.
- Cheap/local/API model for routine triage, summaries, and setup.
- Premium frontier model for hard research reasoning, paper-level judgment, fragile debugging, or when the experiment explicitly studies frontier behavior.
- SageMaker only when the project needs GPU training, direct model weights, hidden states/logits at scale, or local hardware is too weak.

**Workload → instance mapping:**
- Fine-tune 1–7B with LoRA → `ml.g6.xlarge` (~$1.10/hr)
- SSL pretraining, contrastive learning, vision → `ml.g5.4xlarge` (~$1.62/hr)
- Fine-tune 13–34B → `ml.g6.12xlarge` (~$5.67/hr)
- Need 48GB VRAM → `ml.g6e.xlarge` (~$1.86/hr, Studio only)

Always surface spot instances (60–70% savings) for batch jobs with checkpoint support.

End Stage 1 with: "Ready to provision. Say `proceed` to continue, or ask questions first."

---

## Stage 2 — Provision (on `proceed`)

### 2.1 Install AWS CLI if missing

```bash
# macOS
brew install awscli 2>/dev/null || {
  curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/awscliv2.pkg
  sudo installer -pkg /tmp/awscliv2.pkg -target /
}
# Linux
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
  && unzip -q /tmp/awscliv2.zip -d /tmp/ && sudo /tmp/aws/install
```

### 2.2 Authenticate

If not authenticated, run `aws configure`. Confirm with `aws sts get-caller-identity`.

### 2.3 Collect inputs

Ask for (one prompt, not four):
- Handle/username
- Email for budget alerts
- Instance type (confirm the Stage 1 recommendation or let them pick)
- HF token (optional, skip if not needed)

### 2.4 Budget alerts

```bash
aws budgets create-budget \
  --account-id <ACCOUNT_ID> \
  --budget '{"BudgetName":"algoverse-<HANDLE>","BudgetLimit":{"Amount":"200","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[
    {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":25,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<EMAIL>"}]},
    {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":50,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<EMAIL>"}]},
    {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":75,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<EMAIL>"}]}
  ]'
```

### 2.5 S3 bucket

```bash
BUCKET="algoverse-<HANDLE>-<ACCOUNT_ID[:8]>-<REGION>"
aws s3api create-bucket --bucket "$BUCKET" --region <REGION> \
  --create-bucket-configuration LocationConstraint=<REGION>
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
```

Skip `--create-bucket-configuration` for `us-east-1`.

### 2.6 IAM role

```bash
aws iam create-role \
  --role-name "AmazonSageMaker-<HANDLE>" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"sagemaker.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name "AmazonSageMaker-<HANDLE>" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess
aws iam attach-role-policy --role-name "AmazonSageMaker-<HANDLE>" \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### 2.7 Quota request

```bash
aws service-quotas request-service-quota-increase \
  --service-code sagemaker \
  --quota-code <QUOTA_CODE> \
  --desired-value 1 \
  --region <REGION>
```

Instance → quota code:
| Instance | Quota code |
|---|---|
| ml.g6.xlarge | L-1194D77F |
| ml.g5.4xlarge | L-B5D1601B |
| ml.g6.12xlarge | L-62F9E6DE |
| ml.g6e.xlarge | L-E31B2B4A |

### 2.8 Write .sagemaker.env

Write to `~/.sagemaker.env` (chmod 600). Do NOT overwrite if it already exists — ask first.

```
AWS_REGION=<REGION>
S3_BUCKET=<BUCKET>
SM_ROLE_ARN=arn:aws:iam::<ACCOUNT_ID>:role/AmazonSageMaker-<HANDLE>
STUDENT_HANDLE=<HANDLE>
INSTANCE_TYPE=<INSTANCE_TYPE>
PROJECT_SLUG=<project-name>
HF_TOKEN=<token or blank>
```

### 2.9 Wire up the submit script

If the project already has a `sagemaker_submit.py`, confirm the env vars match. If not, scaffold one from the template in this repo:

```bash
cp /path/to/algoverse-aws/templates/sagemaker_submit.py ./sagemaker_submit.py
```

Then run a dry-run smoke test:
```bash
source ~/.sagemaker.env && python sagemaker_submit.py --dry-run
```

### 2.10 Summary card

Print:
```
════════════════════════════════════════
  Setup complete
════════════════════════════════════════
  Account:   <ACCOUNT_ID>
  Region:    <REGION>
  Bucket:    <BUCKET>
  Role:      AmazonSageMaker-<HANDLE>
  Instance:  <INSTANCE_TYPE>
  Quota:     <approved | pending — AWS responds in 24–72h>

Next:
  1. source ~/.sagemaker.env
  2. python sagemaker_submit.py --dry-run
  3. python sagemaker_submit.py --spot
════════════════════════════════════════
```

---

## Hard rules

- Do NOT generate IAM access keys
- Do NOT write to `~/.aws/credentials` directly — use `aws configure`
- Do NOT overwrite an existing `.sagemaker.env` without asking
- Do NOT declare success without a dry-run smoke test
- Do NOT retry failed commands in a loop — diagnose and surface the error
- Diagnose failures yourself before telling the participant to run something manually
