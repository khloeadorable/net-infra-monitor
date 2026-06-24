import json
from pathlib import Path
from typing import TypedDict


class NodeTarget(TypedDict):
    name: str
    type: str
    target: str


DEFAULT_CONFIG_PATH = Path(__file__).parent.parent / "config" / "nodes.json"
EXAMPLE_CONFIG_PATH = Path(__file__).parent.parent / "config" / "nodes.json.example"


def load_targets(config_path: Path = DEFAULT_CONFIG_PATH) -> list[NodeTarget]:
    if config_path.exists():
        with open(config_path) as f:
            return json.load(f)

    if EXAMPLE_CONFIG_PATH.exists():
        with open(EXAMPLE_CONFIG_PATH) as f:
            return json.load(f)

    raise FileNotFoundError(
        f"No node config found. Expected either "
        f"{config_path} or {EXAMPLE_CONFIG_PATH}"
    )