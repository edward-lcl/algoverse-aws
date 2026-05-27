# S3 Conventions

Consistent S3 layout across projects means everyone on a team can find checkpoints, results, and datasets without asking. These are the conventions used across Algoverse GPU projects.

---

## Bucket naming

```
algoverse-<handle>-<account-id[:8]>-<region>
```

Examples:
- `algoverse-edward-506145782-us-east-2`
- `algoverse-jane-doe-abc12345-us-east-2`

Why include the account ID fragment: S3 bucket names are globally unique. Without it, `algoverse-edward-us-east-2` may already be taken by someone else.

---

## Layout

```
s3://<bucket>/
├── data/
│   ├── raw/                    ← original datasets, never modified
│   │   ├── tuh_eeg/            ← one dir per dataset
│   │   ├── ds002778/
│   │   └── ds003490/
│   ├── processed/              ← preprocessed versions (optional cache)
│   └── processed_unified/      ← cross-dataset harmonized segments
├── checkpoints/
│   └── <job-name>/             ← spot instance resume checkpoints
│       ├── model.pt
│       └── optimizer.pt
├── runs/
│   └── <job-name>/
│       └── output/             ← SageMaker output artifacts (model, results)
└── hf_cache/                   ← HuggingFace model cache (FastFile mode)
```

---

## Storage classes

| Data type | Storage class | Why |
|---|---|---|
| Raw datasets (infrequent access) | `STANDARD_IA` | 40% cheaper than STANDARD, accessed once per training run |
| Checkpoints | `STANDARD` | Accessed frequently during training (resume after preemption) |
| Results / final outputs | `STANDARD_IA` | Accessed occasionally for analysis |
| HF model cache | `STANDARD` | Accessed on every cold job start |

Set storage class in the submit script:
```python
# In sagemaker_submit.py
aws s3 sync ./data/ s3://$BUCKET/data/ --storage-class STANDARD_IA
```

Or in the shell upload script:
```bash
aws s3 sync ./data/raw/ s3://$BUCKET/data/raw/ \
  --storage-class STANDARD_IA \
  --exclude ".*"   # exclude rsync temp files and .DS_Store
```

---

## Job naming convention

```
<project-slug>-<experiment-type>-<timestamp>
```

Examples:
- `sjji-eeg-pretrain-1748392000`
- `ybpa-finetune-llama31-1748392000`

Use `int(time.time())` for the timestamp — sortable, unique, no special characters.

```python
import time
job_name = f"{project_slug}-{job_type}-{int(time.time())}"
```

---

## Data upload workflow

**One-time upload (raw datasets):**
```bash
# Upload once, reuse forever
aws s3 sync ./data/raw/ s3://$BUCKET/data/raw/ \
  --storage-class STANDARD_IA \
  --exclude ".*" \
  --no-progress
```

**Incremental sync (add new data):**
```bash
# Only uploads new/changed files — safe to re-run
aws s3 sync ./data/raw/new-dataset/ s3://$BUCKET/data/raw/new-dataset/
```

**Check what's in S3:**
```bash
aws s3 ls s3://$BUCKET/data/raw/ --human-readable --summarize
```

---

## Pulling results back locally

```bash
# Pull results from a specific job
aws s3 sync s3://$BUCKET/runs/<job-name>/output/ ./outputs/<job-name>/

# Pull latest checkpoint (for manual resume)
aws s3 sync s3://$BUCKET/checkpoints/<job-name>/ ./checkpoints/<job-name>/
```

---

## Cost estimate for common datasets

| Dataset | Size | STANDARD_IA/month |
|---|---|---|
| TUH EEG v2.0.1 (full) | ~85GB | ~$1.20 |
| OpenNeuro PD (4 datasets) | ~27GB | ~$0.38 |
| LLM adapter weights (per run) | ~1GB | ~$0.01 |
| Full research project | ~120GB | ~$1.70 |

S3 storage is cheap. The cost to keep your datasets in S3 indefinitely is less than a coffee per month.
