# Algoverse AWS Bootstrap

Get a GPU running on AWS in under an hour. Works for fine-tuning, SSL pretraining, probing, and eval workloads.

---

## Before you start

**Do you actually need a GPU?**

If your project calls an LLM via API (RAG, evals, agent loops), use **Bedrock** — it's dramatically cheaper and requires no setup. Read [`docs/00-bedrock-vs-gpu.md`](docs/00-bedrock-vs-gpu.md) first.

If you need to fine-tune, run open-weight models, extract hidden states, or do contrastive pretraining — continue here.

---

## Two ways to get set up

### Path 1 — One command (fastest, recommended for most people)

```bash
curl -fsSL https://raw.githubusercontent.com/algoverse/algoverse-aws/main/setup.sh | bash
```

Runs in your terminal. Installs the AWS CLI if missing, walks you through credentials, creates your S3 bucket, IAM role, and budget alerts, then prints a summary card. Takes about 20 minutes including AWS account creation.

> **Windows:** run this inside WSL2 (`wsl --install` from Admin PowerShell, then reopen as Ubuntu).

### Path 2 — Claude Code (best for project-specific wiring)

1. Install [Claude Code](https://claude.ai/code)
2. Open your project directory
3. Copy [`AGENTS.md`](AGENTS.md) into your project root
4. Start a Claude Code session — it will read the file and guide you

This path adapts the setup to your specific project (entry point scripts, data layout, instance sizing).

---

## What this sets up

| Resource | What it does |
|---|---|
| AWS account | Your own isolated compute + billing |
| Budget alerts | Emails at 25/50/75% of your credit balance — prevents surprises |
| IAM role | Lets SageMaker read/write your S3 bucket |
| S3 bucket | Cloud storage for datasets and checkpoints |
| SageMaker access | Quota request for GPU instance type |

---

## Instance guide (what GPU to pick)

| Workload | Instance | VRAM | $/hr | Hours on $200 |
|---|---|---|---|---|
| 1–7B LoRA fine-tune | `ml.g6.xlarge` | 24 GB | ~$1.10 | ~180h |
| 1–7B SSL / SimCLR pretraining | `ml.g5.4xlarge` | 24 GB | ~$1.62 | ~123h |
| 13–34B LoRA | `ml.g6.12xlarge` | 96 GB | ~$5.67 | ~35h |
| Large-scale pretraining | `ml.g6e.12xlarge` | 192 GB | ~$10.49 | ~19h |

**Use spot instances** — saves 60–70%. Your script must support checkpoint resume (save every N steps). The submit template handles this automatically.

**Multi-GPU:** requires a separate quota request per instance family. New accounts are often limited to single-GPU L4/L40S. Request `ml.g6.12xlarge` quota via AWS Service Quotas if you need it — expect 24–72h for approval.

---

## Pre-flight checklist — before you spin up a GPU instance

GPU instances bill the moment they start. Run through this first:

- [ ] AWS account created, $200 credits claimed
- [ ] Budget alerts set (25/50/75%) — `setup.sh` does this automatically
- [ ] IAM role created and attached to SageMaker
- [ ] S3 bucket created
- [ ] **Data uploaded to S3** — don't start a GPU job that will spend 2h downloading data
- [ ] Training script runs locally without errors (even CPU-only with 1 batch is fine)
- [ ] `.sagemaker.env` filled in with real values
- [ ] `python sagemaker_submit.py --dry-run` passes
- [ ] GPU quota approved by AWS (check Service Quotas console — new requests take 24–72h)

Only when all boxes are checked should you remove `--dry-run` and pay for GPU time.

---

## After setup — submit your first training job

```bash
# Copy the template into your project
cp /path/to/algoverse-aws/templates/sagemaker_submit.py .
cp /path/to/algoverse-aws/templates/.env.example .env

# Edit .env with your values, then:
python sagemaker_submit.py --job train --spot --dry-run   # preview
python sagemaker_submit.py --job train --spot             # submit
```

---

## Account options: individual vs shared

| Approach | Pros | Cons |
|---|---|---|
| **Individual accounts** (recommended) | Isolated billing, each person controls their spend, no credential sharing | Each person requests their own $200 credits and quotas |
| **Shared IAM keys** | One person manages billing | One person's mistake affects everyone; credential rotation is a headache; AWS bills one person |
| **IAM users on one account** | Shared credits pooled | Complex permissions; one overspend burns the whole team's budget |

**Recommendation:** individual accounts for anything longer than a weekend sprint. The $200 credits are generous enough that each person can run independently.

---

## Repo structure

```
algoverse-aws/
├── README.md               ← you are here
├── setup.sh                ← one-command bootstrap
├── AGENTS.md               ← Claude Code bootstrap prompt
├── docs/
│   ├── 00-bedrock-vs-gpu.md
│   ├── 01-account-setup.md
│   ├── 02-iam-options.md
│   ├── 03-s3-conventions.md
│   └── 04-multi-gpu.md
├── templates/
│   ├── sagemaker_submit.py ← generic training job submit script
│   └── .env.example
└── examples/
    ├── eeg-project/        ← EEG / biosignal SSL pretraining pattern
    └── llm-finetune/       ← LLM LoRA fine-tuning pattern
```

---

## Help

- Something broke during setup → check [`docs/troubleshooting.md`](docs/troubleshooting.md)
- Need a quota increase → [`docs/01-account-setup.md#quotas`](docs/01-account-setup.md#quotas)
- Bedrock instead → [`docs/00-bedrock-vs-gpu.md`](docs/00-bedrock-vs-gpu.md)
- Slack `#aws-help` for anything else

**Hit a problem the docs don’t cover?** [Open a GitHub issue](https://github.com/edward-lcl/algoverse-aws/issues/new) — describe what you ran, what you expected, and what actually happened. This helps improve the bootstrap for everyone.

> **Note:** `setup.sh` and the AGENTS.md path are tested on macOS and Ubuntu. Windows (WSL2) should work but has seen less testing. Report issues if something breaks.
