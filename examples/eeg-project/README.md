# EEG Project — SageMaker Pattern

This example shows how the Algoverse EEG Parkinson's detection project wires up SageMaker.

**Workload:** SimCLR SSL pretraining on TUH EEG corpus (~85GB), then supervised fine-tune on 3 labeled PD datasets.

**Instance:** `ml.g5.4xlarge` (A10G, 24GB VRAM) — good for contrastive learning at this data scale.

**Data layout in S3:**
```
s3://<bucket>/
  data/raw/tuh_eeg/v2.0.1/edf/     ← unlabeled pretraining corpus
  data/raw/ds002778/                ← labeled PD dataset
  data/raw/ds003490/
  data/raw/ds004584/
  data/processed_unified/           ← preprocessed segments (optional cache)
  checkpoints/<job-name>/           ← spot instance resume checkpoints
  runs/<job-name>/output/           ← results and model artifacts
```

**Key decisions:**
- Use spot instances (60–70% cheaper) — SimCLR pretraining is idempotent and checkpoint-friendly
- Upload data once to S3 via `upload_to_s3.sh`, then all training jobs pull from there
- `STANDARD_IA` storage class for raw data (infrequent access, cheaper)

See `sagemaker_submit.py` in the project root for the full submit script.
