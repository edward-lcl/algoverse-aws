# IAM options — individual accounts vs shared keys

## The short version

**Use individual AWS accounts.** It's the cleanest setup, each person controls their spend, and the $200 credits are generous enough that everyone gets their own.

---

## Option A — Individual accounts (recommended)

Each team member creates their own AWS account and claims the $200 credits.

**Pros:**
- Isolated billing — one person can't accidentally spend someone else's budget
- Each person has full control (create/delete resources freely)
- No credential sharing — no security risk
- Credits are free; the only cost is the 15 minutes to set up

**Cons:**
- Each person must go through quota approval separately (24–72h wait)
- No shared S3 storage by default (use a shared bucket with cross-account access if needed)

**When it breaks down:**
- Large team where one central dataset needs to be shared across everyone — in this case, one person hosts the S3 bucket and shares read access via a bucket policy

---

## Option B — Shared IAM keys (avoid for anything longer than a weekend)

One person creates the account and distributes access keys.

**Pros:**
- One quota approval, one setup
- Shared S3 bucket is trivial

**Cons:**
- If the key leaks, the whole account is exposed
- AWS will deactivate accounts with leaked credentials (and the credits disappear with it)
- One person's training run can exhaust the whole budget
- Key rotation affects everyone simultaneously

**If you must do this:**
- Create a dedicated IAM user (not the root account) with limited permissions
- Use `aws configure --profile shared` on each machine (not the default profile)
- Set strict budget alerts at $50 and $100
- Never commit the `.env` file containing the keys

---

## Option C — IAM users on one account

One account, multiple IAM users each with their own keys.

**When this makes sense:** research lab with a single billing account that needs to track per-user spend via cost allocation tags.

**Setup complexity:** high. Requires configuring permission boundaries, cost allocation tags, and separate S3 prefixes per user. Not worth it for a cohort of 5-15 students.

---

## Cross-account S3 sharing (Option A + shared dataset)

If one person has a large dataset in their S3 bucket and others need read access:

```bash
# On the bucket owner's account — add a bucket policy allowing cross-account reads
aws s3api put-bucket-policy --bucket <BUCKET> --policy '{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::<OTHER_ACCOUNT_ID>:root"},
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::<BUCKET>", "arn:aws:s3:::<BUCKET>/*"]
  }]
}'
```

This is the cleanest way to share a dataset without sharing credentials.
