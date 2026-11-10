from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from . import __version__
from .collector import UsageError, collect, collect_cached, load_config


def default_config_path() -> Path:
    root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = root / "dux-ai-usage" / "config.json"
    # The project was called dms-ai-usage; install.sh moves the folder over.
    old = root / "dms-ai-usage" / "config.json"
    return old if old.is_file() and not path.is_file() else path


def default_cache_path() -> Path:
    root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return root / "dux-ai-usage" / "usage.json"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Collect Claude and Codex subscription usage.")
    result.add_argument("--config", type=Path, default=default_config_path())
    result.add_argument("--cache", type=Path, default=default_cache_path())
    result.add_argument(
        "--cached",
        action="store_true",
        help="reuse a fresh shared cache (used by simultaneous bar instances)",
    )
    result.add_argument("--pretty", action="store_true")
    result.add_argument("--version", action="version", version=__version__)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        config_path = args.config.expanduser()
        if not config_path.is_file():
            # Say what is really wrong instead of the generic "not connected".
            raise UsageError("no_config")
        config = load_config(config_path)
        collector = collect_cached if args.cached else collect
        payload = collector(config, args.cache.expanduser())
    except UsageError as exc:
        payload = {
            "schema": 1,
            "bar_text": "AI !",
            "accounts": [],
            "error": exc.code,
        }
        print(json.dumps(payload, separators=(",", ":")))
        return 1
    indent = 2 if args.pretty else None
    separators = None if args.pretty else (",", ":")
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=indent, separators=separators)
    sys.stdout.write("\n")
    # Nothing could be read (the payload says why): scripts can tell from the exit code.
    return 1 if payload.get("error") else 0
