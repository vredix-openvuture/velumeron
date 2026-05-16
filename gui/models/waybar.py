import json
from constants import BARS_JSON, GROUPS_JSON


def read_bars() -> list:
    with open(BARS_JSON) as f:
        return json.load(f)


def read_groups() -> dict:
    with open(GROUPS_JSON) as f:
        return json.load(f)


def write_groups(data: dict):
    with open(GROUPS_JSON, 'w') as f:
        json.dump(data, f, indent=2)
