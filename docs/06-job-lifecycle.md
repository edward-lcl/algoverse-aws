# Job Lifecycle — Submit, Monitor, Debug, Pull

This doc covers the job lifecycle *after* setup is done. Setup (credentials, IAM, S3 bucket, quota) lives in `01-account-setup.md`. This covers what to do before you submit, what to watch while it runs, how to diagnose failures, and how to pull results.

---

## Pre-flight checklist

Run through this before removing `--dry-run`. Each item has killed real jobs.

### 1. Data is in S3 and the right channel is mounted

```bash
# Verify your data exists at the prefix the job will mount
aws s3 ls s3://$S3_BUCKET/data/processed_unified/ --human-readable --summarize
```

**Do not mount raw datasets as a data channel unless the job explicitly needs raw files.**
Raw EEG/video/audio corpora are often 500GB–2TB. A SageMaker instance downloads the entire channel before training starts. If the data exceeds `volume_size`, the job fails with `insufficient disk space` before your code runs. Use pre-processed segments as the channel; mount raw data via boto3 in the training script only if needed.

### 2. Source staging includes everything your script imports

SageMaker packages only the files you whitelist and uploads them as a tarball. If your training script does `from baseline import ...` and `baseline.py` is not in the whitelist, the job fails with `ModuleNotFoundError` immediately at startup.

Audit your entry point's imports and confirm each file or package is either:
- In the `SOURCE_WHITELIST` in your submit script, OR
- Installed as a pip dependency in `requirements.txt`

```python
# In sagemaker_submit.py — typical research project whitelist
SOURCE_WHITELIST = (
    "src",           # your library code
    "experiments",   # entry point scripts
    "scripts",       # helper scripts
    "configs",       # config files
    "baseline.py",   # flat utility scripts imported by experiments
    "train.py",
    "requirements.txt",
)
```

### 3. Training script runs locally on 1 batch

Before paying for GPU time, confirm the script at least initialises and runs one batch:

```bash
# Run a quick smoke on CPU with 1 sample
AJAR_NUM_SAMPLES=1 python experiments/ssl_pilot.py
```

A crash that happens on batch 1 locally will happen on batch 1 in SageMaker too — only locally it costs nothing and the stack trace is immediate.

### 4. All tensors in a batch are the same shape

This is the most common silent bug in multi-dataset ML projects. PyTorch's default collate function calls `torch.stack` which requires every tensor in a batch to have identical shape. If your datasets have different channel counts, different sequence lengths, or different image sizes, **you will get a `RuntimeError: stack expects each tensor to be equal size` crash at the first multi-file batch.**

The fix must be applied at the `Dataset.__getitem__` level, not at the DataLoader level:

```python
# WRONG — only truncates, does not pad. Tensors with C < n_channels crash the batch.
def __getitem__(self, i):
    x = self.samples[i]
    if self.n_channels and x.shape[0] > self.n_channels:
        x = x[:self.n_channels]
    return x

# CORRECT — truncate AND pad to a fixed size
def __getitem__(self, i):
    x = self.samples[i]
    if self.n_channels is not None:
        C = x.shape[0]
        if C > self.n_channels:
            x = x[:self.n_channels]
        elif C < self.n_channels:
            x = torch.nn.functional.pad(x, (0, 0, 0, self.n_channels - C))
    return x
```

This matters any time you mix datasets: clinical EEG (variable montages), multi-source vision (different resolutions), audio (different sample rates). Always define a canonical shape for your experiment and enforce it at load time — not at collation time.

### 5. Dry-run smoke passes

```bash
python sagemaker_submit.py --job pretrain --spot --dry-run
```

Verify the output shows the right: job name, instance, max_hours, source dir, data channel S3 URI.

---

## Submitting

Use `--no-wait` for jobs longer than 30 minutes so the terminal doesn't block:

```bash
python sagemaker_submit.py --job pretrain --spot --max-hours 24 --no-wait
```

Always use `--spot` unless:
- The job has no checkpoint support (spot preemption would lose all progress)
- The instance type has poor spot availability for your region

Save the job name from the output. Everything else — logs, artifacts, status — is keyed off it.

---

## Monitoring

### Check status

```bash
aws sagemaker describe-training-job \
  --training-job-name <job-name> \
  --region $AWS_REGION \
  --query '{Status:TrainingJobStatus,Secondary:SecondaryStatus,Failure:FailureReason}' \
  --output json
```

| Status | Secondary | Meaning |
|---|---|---|
| InProgress | Starting | Instance provisioning / data download |
| InProgress | Downloading | Copying S3 data channels to instance |
| InProgress | Training | Your code is running |
| Completed | Completed | Done, artifacts uploaded to S3 |
| Failed | Failed | See `FailureReason` |
| Stopped | MaxRuntimeExceeded | Hit `max_run` — increase `--max-hours` |
| Stopped | SpotInterruption | Spot instance was preempted — resubmit |

`MaxRuntimeExceeded` is not a failure — it means your code was running fine but ran out of wall-clock time. Increase `--max-hours` and resubmit.

### Tail logs in real time

```bash
aws logs tail /aws/sagemaker/TrainingJobs \
  --log-stream-name-prefix <job-name> \
  --follow \
  --region $AWS_REGION
```

Or in the AWS console: CloudWatch → Log groups → `/aws/sagemaker/TrainingJobs` → filter by job name.

### Push notifications (don't poll — get told)

Polling `describe-training-job` by hand is how jobs fail silently for days. Wire job state changes to email once, and every Completed / Failed / Stopped job notifies you automatically with its failure reason.

This is a one-time setup per account. Email is the default because it needs no extra infrastructure.

```bash
REGION=$AWS_REGION
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
EMAIL=you@example.com

# 1. Topic + email subscription (confirm via the link AWS emails you)
TOPIC=$(aws sns create-topic --region $REGION --name sagemaker-alerts --query TopicArn --output text)
aws sns subscribe --region $REGION --topic-arn "$TOPIC" --protocol email --notification-endpoint "$EMAIL"

# 2. Let EventBridge publish to the topic
aws sns set-topic-attributes --region $REGION --topic-arn "$TOPIC" --attribute-name Policy --attribute-value \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"events.amazonaws.com\"},\"Action\":\"sns:Publish\",\"Resource\":\"$TOPIC\"}]}"

# 3. Rule: fire on terminal training-job states
aws events put-rule --region $REGION --name sagemaker-job-state \
  --event-pattern '{"source":["aws.sagemaker"],"detail-type":["SageMaker Training Job State Change"],"detail":{"TrainingJobStatus":["Completed","Failed","Stopped"]}}'

# 4. Target the topic with a readable message (job name + status + reason)
aws events put-targets --region $REGION --rule sagemaker-job-state --targets \
  "[{\"Id\":\"sns\",\"Arn\":\"$TOPIC\",\"InputTransformer\":{\"InputPathsMap\":{\"name\":\"\$.detail.TrainingJobName\",\"status\":\"\$.detail.TrainingJobStatus\",\"reason\":\"\$.detail.FailureReason\"},\"InputTemplate\":\"\\\"SageMaker job <name> is now <status>. Reason: <reason>\\\"\"}}]"
```

> **Personal agent / digital-twin systems:** if you run an assistant on a chat surface (Discord, Slack, Telegram), you can route these alerts there instead of — or in addition to — email. Point the EventBridge rule at a Lambda (or an SNS→HTTPS subscription) that posts to your channel webhook, so failures land where you already are. Email is the simple default; the chat hook is an optional expansion for people with that infrastructure already standing.

---

## Diagnosing failures

### Step 1 — Read the failure reason

```bash
aws sagemaker describe-training-job \
  --training-job-name <job-name> \
  --region $AWS_REGION \
  --query 'FailureReason' \
  --output text
```

### Common failure patterns

| Symptom | Root cause | Fix |
|---|---|---|
| `ModuleNotFoundError: No module named 'X'` | Module not in source whitelist | Add the file/directory to `SOURCE_WHITELIST` in submit script |
| `insufficient disk space` | Raw data channel too large for `volume_size` | Use pre-processed data channel instead of raw; or increase `volume_size` (costs more) |
| `RuntimeError: stack expects each tensor to be equal size` | Mixed-shape tensors from multi-dataset loading | Add pad+truncate to `__getitem__` (see pre-flight §4) |
| `AlgorithmError: ExitCode 1` with no message | Script crashed at import time | Run the entry point locally first to expose the real error |
| `ClientError: Data download failed` | S3 path doesn't exist or IAM can't access it | Check the S3 URI with `aws s3 ls`; confirm role has S3 read access |
| `ResourceLimitExceeded` | GPU quota not approved | Request quota increase in Service Quotas console; allow 24–72h |
| Stopped / `SpotInterruption` | Spot instance preempted | Not a code failure — resubmit; add checkpoint save/load to survive preemption |
| Stopped / `MaxRuntimeExceeded` | Training takes longer than `max_run` | Increase `--max-hours`; estimate: ~6-7 min/epoch on g5.4xlarge for 180k-segment dataset |
| `InternalServerError: We encountered an internal error` | **Frequently not a transient AWS error.** SageMaker surfaces this when a job runs to completion but exits non-zero and produces no model output. Always check CloudWatch logs before assuming AWS-side. |

### The silent zero-output failure (most dangerous pattern)

A job can show `InProgress → Failed: InternalServerError` even when AWS infrastructure is fine. This happens when your processing code swallows exceptions and produces zero output:

```
# Progress log showing the bug:
[500/68128]  0 segs | 7.0 files/s | ETA 161m | skip=0 err=500   ← 100% error rate

# Progress log showing a working job:
[500/68128] 29,257 segs | 4.2 files/s | ETA 266m | skip=0 err=45  ← small error rate, real output
```

If `err ≈ processed` and `segs = 0`, the bug is in your code, not AWS.

**To diagnose:** download one file and run the processing function locally:

```bash
aws s3 cp s3://$S3_BUCKET/data/raw/<path/to/file> /tmp/test_file --region $AWS_REGION
python3 -c "
from src.preprocess import process_eeg_file
try:
    segs = process_eeg_file('/tmp/test_file', unified=True)
    print('OK:', segs.shape)
except Exception as e:
    print('ERROR:', type(e).__name__, e)
"
```

**Real example (SJJI EEG, 2026-05-29):** `process_eeg_file(unified=True)` called `mne.interpolate_bads()` on channels added via `add_reference_channels()`. TUH EDF files use a `tcp_le` bipolar montage — after channel name normalization, positions were unknown to MNE and interpolation produced NaN/inf arrays. All 68k files silently failed. Five preprocess job attempts all hit `InternalServerError` before the true cause was found. Fix: replace MNE interpolation with zero-padding for missing channels.

### Step 2 — Read CloudWatch logs

The failure reason is often truncated. Full traceback is in CloudWatch:

```bash
aws logs get-log-events \
  --log-group-name /aws/sagemaker/TrainingJobs \
  --log-stream-name "<job-name>/algo-1-<timestamp>" \
  --region $AWS_REGION \
  --query 'events[*].message' \
  --output text | tail -50
```

---

## Pulling results

```bash
# Pull model artifacts (encoder weights, results JSON)
aws s3 sync \
  s3://$S3_BUCKET/runs/<job-name>/output/ \
  ./outputs/<job-name>/

# Unpack the model.tar.gz SageMaker wraps outputs in
tar -xzf ./outputs/<job-name>/output/model.tar.gz -C ./outputs/<job-name>/
```

---

## Runtime estimates (g5.4xlarge, A10G 24GB)

These are empirical — use as a starting point, not a guarantee.

| Workload | Dataset size | Per-epoch time | 100 epochs |
|---|---|---|---|
| SimCLR pretraining | ~18k segments (OpenNeuro only) | ~5–6 min | ~8–10h |
| SimCLR pretraining | ~180k segments (+ TUH subset) | ~6–7 min | ~10–12h |
| Supervised fine-tune (N-LNSO CV) | ~6k labeled segments | ~20–30 min total | — |
| Linear probe (frozen encoder) | ~6k labeled segments | ~10–15 min total | — |

For a 100-epoch pretrain on 180k segments: use `--max-hours 24` with spot. The last ~20% of epochs converge slowly but still move.

---

## Checkpoint support for spot instances

If your job uses spot instances, preemption can kill progress. SageMaker syncs `/opt/ml/checkpoints/` to S3 automatically when `checkpoint_s3_uri` is set. Your training script needs to:

1. Save checkpoints to `/opt/ml/checkpoints/` periodically (e.g. every 5 epochs)
2. On startup, check if a checkpoint exists and resume from it

```python
import os

CHECKPOINT_DIR = os.environ.get("SM_HP_CHECKPOINT_DIR", "/opt/ml/checkpoints")
checkpoint_path = os.path.join(CHECKPOINT_DIR, "latest.pt")

# Save
torch.save({"epoch": epoch, "model": model.state_dict(), ...}, checkpoint_path)

# Resume
if os.path.exists(checkpoint_path):
    state = torch.load(checkpoint_path)
    model.load_state_dict(state["model"])
    start_epoch = state["epoch"] + 1
```

Without checkpoint support, spot preemption restarts training from epoch 0. With it, you lose at most `checkpoint_interval` epochs.
