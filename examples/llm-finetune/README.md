# LLM Fine-tune — SageMaker Pattern

This example shows how the Algoverse YBPA sandbagging project wires up SageMaker.

**Workload:** LoRA fine-tuning on Llama 3.1 8B / Qwen models for sandbagging attack simulation.

**Instance:** `ml.g6.xlarge` (L4, 24GB) for single-model runs; `ml.g6.12xlarge` (4× L4) for sweeps.

**Data layout in S3:**
```
s3://<bucket>/
  checkpoints/<job-name>/          ← LoRA adapters and optimizer state
  runs/<job-name>/output/          ← eval results, sweep artifacts
  hf_cache/                        ← HF model cache (FastFile mode)
```

**Key decisions:**
- Use spot instances with checkpoint resume (HF Trainer saves every N steps by default)
- Mount HF model cache from S3 via FastFile to avoid re-downloading on each run
- Separate S3 prefixes per experiment name for clean artifact management

See `sagemaker_submit.py` in the YBPA repo for the full submit script.
