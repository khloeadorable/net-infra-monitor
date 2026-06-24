"""
Loads the list of monitored nodes from config/nodes.json.

This file is meant to be generated (or hand-edited) after `terraform apply`,
using the real outputs (node_public_ip, s3_bucket_name, etc).
See scripts/sync_targets.py for the automated version.
"""
import json
from pathlib import Path
from typing import TypedDict


class NodeTarget(TypedDict):
    name: str
    type: str  # "http" or "tcp"
    target: str  # URL for http, "host:port" for tcp


DEFAULT_CONFIG_PATH = Path(__file__).parent.parent / "config" / "nodes.json"


def load_targets(config_path: Path = DEFAULT_CONFIG_PATH) -> list[NodeTarget]:
    if not config_path.exists():
        raise FileNotFoundError(
            f"No node config at {config_path}. Run `terraform apply` then "
            f"`python scripts/sync_targets.py` to generate it, or copy "
            f"config/nodes.json.example manually."
        )
    with open(config_path) as f:
        return json.load(f)
