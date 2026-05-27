"""Submit a SageMaker training job for the SJJI EEG project.

Data lives in S3 — training jobs pull from there, no local data needed.
Spot instances save 60-70%; safe if the training script supports checkpoint resume.

Usage:
    python sagemaker_submit.py --job pretrain              # TUH-scale SSL pretraining
    python sagemaker_submit.py --job finetune              # supervised fine-tune on PD datasets
    python sagemaker_submit.py --job eval                  # cross-dataset evaluation
    python sagemaker_submit.py --job ssl_pilot --spot      # quick pilot on spot

Setup (.env or environment):
    AWS_REGION=us-east-2
    S3_BUCKET=sagemaker-us-east-2-506145782110
    SM_ROLE_ARN=arn:aws:iam::506145782110:role/AmazonSageMaker-ExecutionRole-20260509T231091

Data layout expected in S3:
    s3://<bucket>/data/raw/tuh_eeg/          ← full TUH corpus (~1.2TB)
    s3://<bucket>/data/raw/ds002778/
    s3://<bucket>/data/raw/ds003490/
    s3://<bucket>/data/raw/ds004148/
    s3://<bucket>/data/raw/ds004584/
    s3://<bucket>/data/processed_unified/    ← optional: pre-processed segments
"""
import argparse
import os
import shutil
import tempfile
import time

import boto3
import sagemaker
from sagemaker.estimator import Estimator
from sagemaker.inputs import TrainingInput


# --------------------------------------------------------------------------- #
# Job configs: entry_point, instance, max hours, data channels                #
# --------------------------------------------------------------------------- #
JOB_CONFIGS = {
    "pretrain": {
        "entry_point": "experiments/ssl_pilot.py",
        "instance":    "ml.g5.4xlarge",   # A10G 24GB VRAM — good for SimCLR at scale
        "max_hours":   12,
        "data_channels": ["tuh_eeg", "processed_unified"],
        "description": "TUH-scale SimCLR SSL pretraining (domain-adversarial)",
    },
    "finetune": {
        "entry_point": "experiments/ssl_pilot.py",  # update when dedicated script exists
        "instance":    "ml.g5.xlarge",
        "max_hours":   6,
        "data_channels": ["labeled_pd", "processed_unified"],
        "description": "Supervised fine-tune on PD datasets (ds002778/3490/4584)",
    },
    "eval": {
        "entry_point": "experiments/ssl_pilot.py",  # update when dedicated script exists
        "instance":    "ml.g5.xlarge",
        "max_hours":   3,
        "data_channels": ["labeled_pd", "processed_unified"],
        "description": "Cross-dataset evaluation (leave-one-dataset-out)",
    },
    "ssl_pilot": {
        "entry_point": "experiments/ssl_pilot.py",
        "instance":    "ml.g5.xlarge",
        "max_hours":   4,
        "data_channels": ["processed_unified"],
        "description": "Quick SSL pilot (no TUH, use pre-processed segments only)",
    },
}

# S3 data channel prefixes — must match the S3 layout described above
DATA_CHANNEL_S3_PREFIXES = {
    "tuh_eeg":           "data/raw/tuh_eeg",
    "labeled_pd":        "data/raw",           # includes ds002778 / ds003490 / ds004584
    "processed_unified": "data/processed_unified",
}

# Source code whitelist — keeps the upload small (no data, no __pycache__)
SOURCE_WHITELIST = (
    "src",
    "experiments",
    "scripts",
    "configs",
    "requirements.txt",
    "pyproject.toml",
    "README.md",
)


# --------------------------------------------------------------------------- #
# Helpers                                                                      #
# --------------------------------------------------------------------------- #

def stage_source_dir(repo_root: str) -> str:
    """Copy only whitelisted paths to a temp dir. Avoids uploading GBs of data."""
    staging = tempfile.mkdtemp(prefix="sm-eeg-source-")
    for name in SOURCE_WHITELIST:
        src = os.path.join(repo_root, name)
        if not os.path.exists(src):
            continue
        dst = os.path.join(staging, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns(
                "__pycache__", "*.pyc", ".pytest_cache",
                "*.npz", "*.edf", "*.EDF",  # no raw EEG in source upload
            ))
        else:
            shutil.copy2(src, dst)
    return staging


def build_data_inputs(channels: list[str], bucket: str) -> dict:
    """Build SageMaker TrainingInput objects for each requested data channel."""
    inputs = {}
    for ch in channels:
        prefix = DATA_CHANNEL_S3_PREFIXES.get(ch)
        if prefix is None:
            print(f"  [warn] Unknown data channel '{ch}', skipping.")
            continue
        uri = f"s3://{bucket}/{prefix}/"
        inputs[ch] = TrainingInput(
            s3_data=uri,
            s3_data_type="S3Prefix",
            input_mode="File",   # FastFile mode available if data is accessed sequentially
        )
        print(f"  data[{ch}]: {uri}")
    return inputs


# --------------------------------------------------------------------------- #
# Main                                                                         #
# --------------------------------------------------------------------------- #

def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--job", choices=list(JOB_CONFIGS.keys()), default="ssl_pilot",
                   help="Job preset to run (see JOB_CONFIGS above)")
    p.add_argument("--entry-point", default=None,
                   help="Override entry point script (relative to repo root)")
    p.add_argument("--instance", default=None,
                   help="Override instance type")
    p.add_argument("--max-hours", type=int, default=None,
                   help="Override max runtime hours")
    p.add_argument("--spot", action="store_true",
                   help="Use spot instances (60-70%% cheaper; script must support checkpoint resume)")
    p.add_argument("--no-wait", action="store_true",
                   help="Submit async; poll with describe-training-job")
    p.add_argument("--job-name", default=None,
                   help="Custom job name (default: sjji-eeg-<timestamp>)")
    p.add_argument("--dry-run", action="store_true",
                   help="Print config without submitting")
    args = p.parse_args()

    cfg = JOB_CONFIGS[args.job]
    entry_point  = args.entry_point or cfg["entry_point"]
    instance     = args.instance    or cfg["instance"]
    max_hours    = args.max_hours   or cfg["max_hours"]
    data_channels = cfg["data_channels"]

    region   = os.environ.get("AWS_REGION", "us-east-2")
    bucket   = os.environ.get("S3_BUCKET",  "sagemaker-us-east-2-506145782110")
    role_arn = os.environ.get(
        "SM_ROLE_ARN",
        "arn:aws:iam::506145782110:role/service-role/AmazonSageMaker-ExecutionRole-20260509T231091",
    )

    job_name = args.job_name or f"sjji-eeg-{args.job}-{int(time.time())}"

    # PyTorch 2.4 DLC (CUDA 12.4). Works for SimCLR + MNE post-processing.
    # Upgrade: https://github.com/aws/deep-learning-containers/blob/master/available_images.md
    image_uri = (
        f"763104351884.dkr.ecr.{region}.amazonaws.com/"
        f"pytorch-training:2.4.0-gpu-py311-cu124-ubuntu22.04-sagemaker"
    )

    repo_root   = os.path.dirname(os.path.abspath(__file__))
    staging_dir = stage_source_dir(repo_root)

    print(f"\n{'='*60}")
    print(f"  Job:      {job_name}")
    print(f"  Preset:   {args.job} — {cfg['description']}")
    print(f"  Entry:    {entry_point}")
    print(f"  Instance: {instance}{' (spot)' if args.spot else ' (on-demand)'}")
    print(f"  Max run:  {max_hours}h")
    print(f"  Source:   {staging_dir}")
    print(f"  Region:   {region}  Bucket: {bucket}")

    data_inputs = build_data_inputs(data_channels, bucket)

    if args.dry_run:
        print("\n[dry-run] Not submitting.")
        return

    sess = sagemaker.Session(boto_session=boto3.Session(region_name=region))

    estimator = Estimator(
        image_uri=image_uri,
        role=role_arn,
        instance_type=instance,
        instance_count=1,
        volume_size=200,   # GB — EDF files are large; increase for full TUH jobs
        max_run=max_hours * 3600,
        use_spot_instances=args.spot,
        max_wait=(max_hours * 3600 + 3600) if args.spot else None,
        checkpoint_s3_uri=f"s3://{bucket}/checkpoints/{job_name}/" if args.spot else None,
        sagemaker_session=sess,
        output_path=f"s3://{bucket}/runs/{job_name}/output/",
        base_job_name="sjji-eeg",
        entry_point=entry_point,
        source_dir=staging_dir,
        environment={
            "SM_JOB_NAME":   job_name,
            "S3_BUCKET":     bucket,
            "DATA_CHANNELS": ",".join(data_channels),
            # Point MNE/cache dirs at instance scratch
            "MNE_DATA":      "/opt/ml/input/data",
            "RESULTS_DIR":   "/opt/ml/model",
        },
        tags=[
            {"Key": "project", "Value": "sjji-eeg"},
            {"Key": "job-preset", "Value": args.job},
        ],
    )

    print(f"{'='*60}\n")
    estimator.fit(
        inputs=data_inputs if data_inputs else None,
        job_name=job_name,
        wait=not args.no_wait,
        logs="All" if not args.no_wait else None,
    )

    if args.no_wait:
        print(f"\nSubmitted async. Poll:")
        print(f"  aws sagemaker describe-training-job --training-job-name {job_name} --region {region}")
    else:
        print(f"\nDone. Pull results:")
        print(f"  aws s3 sync s3://{bucket}/runs/{job_name}/output/ ./outputs/{job_name}/")


if __name__ == "__main__":
    main()
