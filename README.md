# Algoverse Experiment Bootstrap

Project-local SOP for choosing, launching, monitoring, and shutting down research compute. It can use local machines, API models, Bedrock/OpenRouter, or SageMaker depending on the experiment.

---

## Recommended use

Clone this repo inside the research project you are setting up:

```bash
cd /path/to/your-project
git clone https://github.com/edward-lcl/algoverse-aws .algoverse
```

Then run the setup from the project root:

```bash
python .algoverse/scripts/local_compute_check.py
```

If you are using an agent, point it at the project root and this repo together:

```text
Use .algoverse/AGENTS.md as the compute setup SOP for this project.
First inspect the project artifact, then recommend local compute, API models, or SageMaker.
```

This keeps the SOP next to the actual code/proposal, so the agent can infer entry points, data layout, team handoffs, and cost risk instead of asking the researcher to fill out a long form.

---

## Before you spend cloud money

**Do you actually need remote compute?**

Start with [`docs/05-local-compute-and-model-routing.md`](docs/05-local-compute-and-model-routing.md). Many projects can run early experiments locally or with cheap API models before using SageMaker.

If the project calls an LLM via API (RAG, evals, agent loops), use the model routing policy in [`docs/05-local-compute-and-model-routing.md`](docs/05-local-compute-and-model-routing.md). Premium frontier models are allowed and encouraged when the research question needs them; they should be deliberate, not the default for every loop.

If you need to fine-tune, run open-weight models, extract hidden states, or do contrastive pretraining — continue here.

---

## Two ways to get set up

### Path 1 — One command (fastest, recommended for most people)

```bash
curl -fsSL https://raw.githubusercontent.com/algoverse/algoverse-aws/main/setup.sh | bash
```

Runs in your terminal. Installs the AWS CLI if missing, walks you through credentials, creates your S3 bucket, IAM role, and budget alerts, then prints a summary card. Takes about 20 minutes including AWS account creation.

> **Windows:** run this inside WSL2 (`wsl --install` from Admin PowerShell, then reopen as Ubuntu).

### Path 2 — Agent-guided setup (best for project-specific wiring)

1. Install [Claude Code](https://claude.ai/code)
2. Open your project directory
3. Clone this repo as `.algoverse/`
4. Start a coding-agent session and tell it to use `.algoverse/AGENTS.md`

This path adapts the setup to your specific project (entry point scripts, data layout, local compute, model routing, instance sizing, and team split).

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

## Compute routing guide

| Need | First route | Cloud route |
|---|---|---|
| Prompting, triage, summaries | Cheap/local/API model | Bedrock/OpenRouter if needed |
| Frontier reasoning, hard research synthesis | Premium frontier model | OpenRouter/direct provider |
| Local model evals, hidden states, small open models | Best team laptop/workstation | SageMaker if local hardware is too weak |
| 1–7B LoRA fine-tune | Local GPU if >=16-24GB VRAM | `ml.g6.xlarge` |
| 1–7B SSL / SimCLR pretraining | Local GPU only for pilots | `ml.g5.4xlarge` |
| 13–34B LoRA | Usually remote | `ml.g6.12xlarge` |
| Large-scale pretraining | Remote | `ml.g6e.12xlarge` or larger |

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
├── scripts/
│   └── local_compute_check.py
├── docs/
│   ├── 00-bedrock-vs-gpu.md
│   ├── 01-account-setup.md
│   ├── 02-iam-options.md
│   ├── 03-s3-conventions.md
│   ├── 04-multi-gpu.md
│   └── 05-local-compute-and-model-routing.md
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

> **Note:** `setup.sh` is tested on macOS. Linux and Windows (WSL2) are untested — if something breaks, [open an issue](https://github.com/edward-lcl/algoverse-aws/issues/new).
