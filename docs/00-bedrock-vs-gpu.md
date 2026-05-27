# Bedrock vs GPU — which do you need?

**Start here before requesting GPU quota.** Most Algoverse projects don't need a GPU.

---

## Use Bedrock (API) if you are...

- Calling an LLM to evaluate outputs, run evals, or build agent loops
- Doing RAG or retrieval-augmented generation
- Running benchmarks where you pass text in and get text out
- Doing prompt engineering or few-shot experiments

Bedrock charges per token. No setup beyond an API key. $200 in credits = a lot of tokens.

| Model | Cost | What $200 buys |
|---|---|---|
| Claude Haiku 4.5 | ~$1/M input, ~$5/M output | ~200M input tokens |
| Claude Sonnet 4.6 | ~$3/M input, ~$15/M output | ~67M input tokens |
| GPT-class 20B | ~$0.15/M input, ~$0.60/M output | ~1B input tokens |

**How to use it:**
```python
import boto3
client = boto3.client("bedrock-runtime", region_name="us-east-1")
```

## Use a GPU if you are...

- Fine-tuning an open-weight model (LoRA, full fine-tune, RLHF)
- Running SSL / contrastive pretraining (SimCLR, DINO, etc.)
- Extracting hidden states, attention maps, or logits from a local model
- Running a model that isn't available on Bedrock
- Doing mechanistic interpretability (need direct model access)

GPU instances bill per hour whether you're using them or not. An idle g6.xlarge running overnight costs ~$8.

---

## Decision flowchart

```
Do you need to modify model weights?
├── No → Do you need logits/hidden states/attention?
│   ├── No → Use Bedrock
│   └── Yes → Use GPU (need direct model access)
└── Yes → Use GPU
```

If you're unsure, ask in `#aws-help` before requesting quota.
