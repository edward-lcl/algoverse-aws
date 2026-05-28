# Local Compute And Model Routing

Use this before spending cloud money. The goal is not to avoid frontier models or SageMaker. The goal is to spend them on the parts of the research where they actually matter.

## Intake

Ask for one project artifact first:

- A GitHub repo link
- A local project path
- A zip file
- A pasted PI-approved proposal or markdown brief

Avoid a long questionnaire. Inspect the artifact, infer the likely experiment type, then ask only for missing blockers.

## Local Compute Check

Run:

```bash
python .algoverse/scripts/local_compute_check.py
```

For a team, run it on each person's machine and use the best available hardware for pilots, preprocessing, local inference, or debugging.

What matters:

- RAM: 16GB is baseline, 32GB is comfortable, 64GB+ is good for data-heavy work.
- Apple Silicon unified memory: useful for local inference and medium experiments, but not a substitute for large CUDA training.
- NVIDIA VRAM: 8GB is small, 12-16GB can pilot many workloads, 24GB can run meaningful 1-7B work, 48GB+ is serious local compute.
- Disk: large datasets need external disk or S3; do not fill a laptop to 99%.

If nobody has enough local hardware, go cloud earlier. If one teammate has a strong GPU, make that person the local pilot owner.

## Model Routing Policy

Use the cheapest capable model first for routine work, but do not avoid premium frontier models when the research needs them.

| Work | Default | Escalate when |
|---|---|---|
| File triage, summaries, setup help | Local/small/cheap API model | It misses important structure |
| Routine code edits | Mid-tier coding model | Cross-module reasoning or fragile infra |
| Research synthesis | Strong frontier model | Usually justified for paper-level judgment |
| Experimental variable under measurement | Fixed model chosen by protocol | Never swap casually |
| LLM API eval loops | Cheap model or target model only | The eval specifically studies frontier behavior |
| Hidden states/logits/local models | Local GPU if viable | Local hardware cannot run the model |

Premium frontier use is acceptable for research decisions, hard debugging, experimental design, and paper framing. It should be explicit in the run notes so costs are explainable.

## Experiment Profiles

Classify the project before selecting compute:

- API-only LLM project: Bedrock/OpenRouter/direct provider; no SageMaker GPU unless hidden states or local weights are required.
- Local inference/eval: run local compute check; use local if the model fits with headroom.
- Fine-tuning: prefer SageMaker or a strong local NVIDIA box; require checkpoint resume before spot.
- SSL/pretraining: SageMaker or dedicated workstation; require data-size and volume-size preflight.
- Preprocessing pipeline: can often run on CPU instances, EC2, or local machines with enough disk; avoid expensive GPU hours.
- Post-processing/eval/writeup: usually local or cheap API models.

## Team Split

For teams of 2-4:

- Data owner: dataset access, S3 layout, preprocessing, storage cleanup.
- Training owner: submit jobs, monitor logs, optimize GPU, checkpoint recovery.
- Evaluation owner: metrics, plots, ablations, result tables.
- Mentor/lead: IAM, budgets, quota escalation, destructive cleanup approvals.

For two-person teams, combine data+training and eval+writeup.

## Guardrails

- Require a first-minute smoke log: selected device, GPU name, batch size, batch time, and ETA.
- Stop a run immediately if it falls back to CPU on a GPU instance.
- Compare S3 input size to SageMaker volume size before launch.
- Do not mount raw multi-terabyte data into a training job unless the code streams it intentionally.
- Use spot only when checkpoint resume exists.
- Record model choice and why it was cheap/local/frontier.

