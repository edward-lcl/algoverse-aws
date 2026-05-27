# **AWS Credits (read this first)**

## **How to claim the $200**

When you sign up for a brand-new AWS account, you are offered two account plans:

* **Free plan** up to $200 in credits, valid for 6 months or until credits run out. After that the account closes automatically. Pick this one if you do not want any chance of being charged.  
* **Paid plan is the** same $200 in credits, but after credits run out you are billed pay-as-you-go. Pick this only if you understand that.

The $200 is split into two buckets:

1. **$100 awarded on sign-up** you get this just for creating the account.  
2. **Up to $100 more from onboarding activities** five activities worth $20 each. They include things like launching an EC2 instance, creating an RDS database, deploying a Lambda function, calling a Bedrock model, and setting up a budget. Credits appear within \~10 minutes of completing each activity.

Rules to know:

* Credits only apply to a new account. If you already have an AWS account, this does not retroactively give you credits.  
* Use your personal email. The credits are tied to the account, not the person.  
* The credits are general  they work for both Bedrock and GPU instances.  
* Onboarding activities must be completed within **6 months** of account creation.  
* Credits expire **12 months** after the account is created  even if you have not spent them.

## **Set a budget alert before doing anything else**

Go to **Billing, then Budgets** and create budget alerts at **$50, $100, and $150**. AWS will email you when you cross each threshold. If you forget to do this and leave a GPU running, you can blow through $300 in a weekend without realizing it.

## **What $200 actually buys you**

There are two ways to use AI on AWS, and the budget math is very different.

### [**Path A: Bedrock (use a hosted model via API)**](https://docs.google.com/document/d/1KPKjQWSi5KzSFLFRvwS7p_Vut97u9F2wIksBh6sRl-o/edit?usp=sharing)

Bedrock charges per token. There is no per-instance cost and no "per model" subscription. You can call **any of the 100+ models** in the catalog from the same account your credits just deplete based on how many tokens you send and receive.

Approximate prices (US-East, on-demand, late 2025):

| Model | Input ($/M tokens) | Output ($/M tokens) | What $200 gets you |
| ----- | ----- | ----- | ----- |
| gpt-oss-120b | \~$0.15 | \~$0.60 | \~1B input or \~330M output tokens |
| Claude Haiku 4.5 | \~$1 | \~$5 | \~200M input or \~40M output tokens |
| Claude Sonnet 4.6 | \~$3 | \~$15 | \~67M input or \~13M output tokens |
| Claude Opus 4.7 | \~$15 | \~$75 | \~13M input or \~2.6M output tokens |

For most research projects (RAG, evals, prompting experiments), Bedrock is the right path. $200 is a lot of tokens.

### [**Path B GPUs on SageMaker (train or self-host an open model)**](https://docs.google.com/document/d/1AUmEc3MXjE_zr-ypIAoxNZnDI5BL5OOWzYZ4G-fSxW0/edit?usp=sharing)

This is the path you take if you genuinely need to **fine-tune** a model or run an open-weights model that isn't on Bedrock. It is much more expensive per dollar than Bedrock.

Quotas start at **zero**. You must request a quota increase for each instance type before you can launch it (the GPU PDF walks through this). For A100/H100 instances, AWS rarely approves quota on a brand-new $200 account  assume you will be limited to **L4 and L40S** unless you have a specific reason and a working dialog with AWS support.

Approximate SageMaker on-demand pricing (US-East). SageMaker is \~20% more expensive than raw EC2 because it includes orchestration:

| Instance | GPUs | VRAM | $/hr | Hours on $200 |
| ----- | ----- | ----- | ----- | ----- |
| ml.g6.xlarge | 1× L4 | 24 GB | \~$1.10 | \~180 hr (7.5 days) |
| ml.g6.12xlarge | 4× L4 | 96 GB | \~$5.67 | \~35 hr |
| ml.g6e.xlarge | 1× L40S | 48 GB | \~$1.86 | \~107 hr |
| ml.g6e.12xlarge | 4× L40S | 192 GB | \~$10.49 | \~19 hr |
| ml.p4d.24xlarge | 8× A100 (40 GB) | 320 GB | \~$37.69 | \~5 hr |
| ml.p4de.24xlarge | 8× A100 (80 GB) | 640 GB | \~$40+ | \~5 hr |
| ml.p5.48xlarge | 8× H100 | 640 GB | \~$55+ | \~3.5 hr |

Sanity check: a single overnight run on a p4d (8× A100) costs more than your **entire** credit balance. If you only need to fine-tune a 7B model, **start with one L40S**, not eight A100s.

## 

| You want to... | Use this |
| ----- | ----- |
| Call an LLM from a script for a research project | Bedrock |
| Run evals over a benchmark | Bedrock |
| Build a RAG pipeline | Bedrock \+ S3 |
| Fine-tune a 1B–7B model with LoRA | 1× L4 or 1× L40S |
| Fine-tune a 13B–34B model | 4× L40S |
| Fine-tune a 70B+ model | 8× A100  quota is hard to get; first try LoRA on smaller hardware |
| Train from scratch | You do not have the budget for this on $200. Talk to your mentor. |

**Things that will burn your credit and surprise you**

* **Idle SageMaker notebooks**. The notebook bills *while it is running*, not while you are typing. Closing your laptop does not stop it. Always click **Stop** when you are done.  
* **EBS volumes left attached** to stopped instances. They cost a few cents per GB-month, which adds up if you have several 200 GB volumes hanging around.  
* **Wrong region**. Pricing varies by region. Stick to `us-east-1` (N. Virginia) for the cheapest GPU rates.  
* **Picking "Amazon SageMaker" instead of "SageMaker AI"** in the console. The GPU PDF calls this out  pay attention to it.  
* **Choosing the Paid plan and forgetting**. After your credits run out you start being charged. Use the Free plan unless you have a real reason not to.

# **Handing off your work if you run out of credits**

Credits are tied to the AWS account, not the project. They are **not transferable** between accounts. If you burn through your $200, the standard move is to hand the project off to a teammate whose account is still fresh and have them continue from there.

The handoff works because most of what matters lives outside the AWS account itself  your code is in Git, and your data and checkpoints should already be in S3. The teammate creates a new account, claims their own $200, pulls in the artifacts, and resumes.

A few important rules:

* **Do not create a second AWS account for yourself** to get another $200. The AWS Service Terms explicitly state that promotional credits "may be applied only to your own AWS account" and may not be sold, rented, or transferred violation results in the credits being **revoked**. The handoff is only legitimate when it is a *different teammate* with their own identity and payment method.  
* **Quotas do not transfer.** Your teammate's new account starts at zero quota for every GPU instance type, just like yours did. They must request quota again on day one, which can take 1–2 days. Plan around that lead time  don't hand off the night before a deadline. (The Service Quotas template feature only works within an AWS Organization, which student accounts won't have.)  
* **Native Bedrock fine-tuned models do not transfer.** If you used Bedrock's built-in fine-tuning, the model artifacts live in Bedrock-managed storage and you cannot export the raw weights. The fix is to **keep your training data in S3** and have your teammate re-run the fine-tuning job on their account. (If you instead used Bedrock Custom Model Import  where you brought your own weights from Hugging Face  those weights are already in your S3 bucket and can be transferred normally.)  
* **One legitimate way to share credits:** if both you and your teammate set up your accounts inside the same AWS Organization with consolidated billing *before* spending starts, credits can be shared across member accounts. This is the only AWS-sanctioned credit-sharing path, and it's overkill for most student projects  easier to just hand off the artifacts.

### **What to do before the handoff**

1. **Push all code to GitHub.** Add your teammate as a collaborator.  
2. **Move everything important into S3**  datasets, training checkpoints, eval results, logs. Anything sitting only on a SageMaker notebook's local disk dies when the notebook is deleted.  
3. **Write a short handoff note** that lists: the S3 bucket name(s), the regions you used, the instance types you had quota for, the Bedrock models you used, and any environment variables / API keys (rotated for the new account).

### **Three ways to transfer S3 data to the new account**

In rough order of preference:

1. **Cross-account S3 access (cleanest).** On the old account, attach a bucket policy granting read access to the new account's IAM user/role. The teammate then runs `aws s3 sync s3://old-bucket s3://new-bucket` from their account. No data leaves AWS, so no egress charges. Works for any size.  
2. **Download and re-upload (simple, works at any size but slow and uses your laptop bandwidth).** `aws s3 sync s3://old-bucket ./local` on your machine, then `aws s3 sync ./local s3://new-bucket` from your teammate's. AWS gives you **the first 100 GB/month of internet egress for free** across the whole account, so for most student datasets the transfer costs $0. Above 100 GB it's $0.09/GB (e.g. a 500 GB dataset \= 400 GB billable \= $36 charged to the *old* account).  
3. **Pre-signed URLs (for a few specific files).** Generate a time-limited download URL with `aws s3 presign s3://bucket/key`, send it to your teammate, they `wget` it. Good for handing off a single trained model checkpoint without setting up cross-account IAM.

### **What to do on the receiving side**

1. Sign up for a new AWS account, claim the $200 (see top of this doc).  
2. Set the budget alerts immediately.  
3. Request quota for the same instance types in the same region you'll be using.  
4. Pull the code from GitHub, pull the data from S3 using one of the methods above.  
5. Generate a fresh Bedrock API key from the Quickstart.

## **Quick checklist before you start**

1. Sign up with a new account, pick the Free plan. You start with $100.  
2. Complete the five onboarding activities ($20 each) to claim the remaining $100. The "create a budget" activity is one of them to do first because it kills two birds with one stone.  
3. Go to Billing, Budgets and set alerts at $50, $100, $150.  
4. Decide: Bedrock (path A) or GPU (path B)?  
5. If GPU: request quota for **the specific instance type you need** in **the specific region** you'll use, before you do anything else. Quota requests can take a day or two.  
6. If Bedrock: generate the API key from Quickstart (see Bedrock PDF) and start sending requests.

Once you've done this, continue to the two PDFs in this folder for the click-through walkthroughs.

