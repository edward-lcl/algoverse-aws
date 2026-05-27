# Multi-GPU on SageMaker

## When you actually need it

Multi-GPU training makes sense when:
- Single-GPU run takes >24h and you need results sooner
- Model doesn't fit in single-GPU VRAM (use model parallelism)
- You have a very large dataset and want data parallelism

For most Algoverse projects (fine-tuning 7B models, EEG pretraining, probing studies), **one L4 or L40S is enough**.

---

## The quota problem

AWS assigns GPU quotas per instance type, per region. New accounts start at **zero**.

| Instance | Quota code | Typical approval time |
|---|---|---|
| ml.g6.xlarge (1× L4) | L-1194D77F | 24–72h |
| ml.g5.4xlarge (1× A10G) | L-B5D1601B | 24–72h |
| ml.g6.12xlarge (4× L4) | L-62F9E6DE | 24–72h (sometimes denied) |
| ml.g6e.xlarge (1× L40S) | L-E31B2B4A | 24–72h, Studio only |
| ml.p4d.24xlarge (8× A100) | — | Often denied on new accounts |

Request via AWS Service Quotas console or CLI:
```bash
aws service-quotas request-service-quota-increase \
  --service-code sagemaker \
  --quota-code L-62F9E6DE \
  --desired-value 1 \
  --region us-east-2
```

You'll get an email. Can take 24–72h. A100/H100 instances are frequently denied on $200 accounts — plan around L4/L40S.

---

## Enabling multi-GPU in your training job

SageMaker training jobs support multi-GPU via `instance_count` (multiple instances) or multi-GPU instances (`ml.g6.12xlarge` has 4× L4).

### Data parallel (most common)

```python
# sagemaker_submit.py — switch to a 4-GPU instance
estimator = Estimator(
    instance_type="ml.g6.12xlarge",   # 4× L4, 96GB
    instance_count=1,                  # one machine, 4 GPUs
    ...
)
```

In your training script, use `torchrun` or `accelerate launch`:
```python
# train.py
from accelerate import Accelerator
accelerator = Accelerator()
model, optimizer, dataloader = accelerator.prepare(model, optimizer, dataloader)
```

Launch via SageMaker by updating your entry point:
```python
# In sagemaker_submit.py
estimator = Estimator(
    ...
    entry_point="train.py",
    distribution={"torch_distributed": {"enabled": True}},
)
```

### Multi-node (2+ instances)

More complex — each node needs to communicate. Adds ~5min startup overhead and requires your script to handle `RANK`, `WORLD_SIZE`, `MASTER_ADDR`. Not recommended unless single-node 4-GPU isn't enough.

```python
estimator = Estimator(
    instance_type="ml.g6.12xlarge",
    instance_count=2,   # 2 machines × 4 GPUs = 8 GPUs total
    distribution={"torch_distributed": {"enabled": True}},
    ...
)
```

---

## Cost vs. time tradeoff

| Setup | $/hr | 10h job cost | Speedup vs. 1-GPU |
|---|---|---|---|
| 1× ml.g6.xlarge | $1.10 | $11 | 1× |
| 4× ml.g6.12xlarge | $5.67 | $57 | ~3.5× (not linear) |
| 1× ml.g6.xlarge (spot) | ~$0.35 | $3.50 | 1× |
| 4× ml.g6.12xlarge (spot) | ~$1.90 | $19 | ~3.5× |

Spot on a single GPU is almost always the best value for Algoverse projects.
