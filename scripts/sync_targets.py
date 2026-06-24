#!/usr/bin/env python3
"""
Reads `terraform output -json` and writes config/nodes.json so the
dashboard always points at whatever infrastructure actually exists.

Usage (from repo root, after `terraform apply` in terraform/):
    python scripts/sync_targets.py
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
TF_DIR = ROOT / "terraform" / "environments" / "dev"
OUTPUT_PATH = ROOT / "config" / "nodes.json"


def get_terraform_outputs() -> dict:
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=TF_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def main() -> None:
    try:
        outputs = get_terraform_outputs()
    except subprocess.CalledProcessError as e:
        print(f"terraform output failed: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("terraform CLI not found. Install it and run `terraform apply` first.", file=sys.stderr)
        sys.exit(1)

    node_url = outputs.get("node_health_url", {}).get("value")
    bucket_name = outputs.get("s3_bucket_name", {}).get("value")

    if not node_url:
        print("No node_health_url in terraform output. Did `terraform apply` succeed?", file=sys.stderr)
        sys.exit(1)

    targets = [
        {"name": "EC2-Health-Node", "type": "http", "target": node_url},
    ]
    if bucket_name:
        targets.append(
            {
                "name": "S3-Target",
                "type": "http",
                "target": f"https://{bucket_name}.s3.amazonaws.com/",
            }
        )

    OUTPUT_PATH.write_text(json.dumps(targets, indent=2) + "\n")
    print(f"Wrote {len(targets)} targets to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
