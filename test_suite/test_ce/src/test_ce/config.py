"""Configuration loading for the test suite.

Reads a connection file produced by the deployments/ framework.
"""

import json
import logging
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from azure.mgmt.core.tools import parse_resource_id
from neo4j import Driver, GraphDatabase

logger = logging.getLogger(__name__)


def _find_repo_root() -> Path:
    """Walk up from this file to find the repository root (.git directory)."""
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise FileNotFoundError(
        "Could not locate repository root (no .git directory found)"
    )


def _results_dir() -> Path:
    """Return the results directory path."""
    results_dir = _find_repo_root() / "deployments" / ".arm-testing" / "results"
    if not results_dir.exists():
        raise FileNotFoundError(f"Results directory not found: {results_dir}")
    return results_dir


def _find_connection_file(filename: str | None) -> Path:
    """Locate a connection file by name, or the most recent one if not specified."""
    rd = _results_dir()

    if filename:
        path = rd / filename
        if not path.exists():
            raise FileNotFoundError(f"Connection file not found: {path}")
        logger.info("Using connection file: %s", path)
        return path

    matches = sorted(
        rd.glob("connection-*.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not matches:
        raise FileNotFoundError(f"No connection files in {rd}")

    logger.info("Using latest connection file: %s", matches[0].name)
    return matches[0]


def _extract_output(outputs: dict, key: str, default: str = "") -> str:
    """Extract a value from raw ARM template outputs.

    ARM outputs are stored as ``{"key": {"value": "..."}}`` dicts.
    """
    entry = outputs.get(key)
    if entry is None:
        return default
    if isinstance(entry, dict):
        return str(entry.get("value", default))
    return str(entry)


def _subscription_from_resource_id(resource_id: str) -> str:
    """Extract the subscription ID from a full Azure resource ID."""
    if not resource_id:
        return ""
    parsed = parse_resource_id(resource_id)
    return parsed.get("subscription", "")


@dataclass(frozen=True)
class StackConfig:
    """Immutable deployment configuration."""

    browser_url: str
    neo4j_uri: str
    username: str
    password: str
    host: str
    resource_group: str = ""
    vm_name: str = ""
    data_disk_id: str = ""
    subscription_id: str = ""

    @property
    def has_azure_context(self) -> bool:
        """True when enough Azure metadata is present for resource checks."""
        return bool(self.resource_group and self.vm_name and self.subscription_id)

    @contextmanager
    def driver(self) -> Generator[Driver, None, None]:
        """Context manager for a Neo4j Bolt driver."""
        drv = GraphDatabase.driver(
            self.neo4j_uri, auth=(self.username, self.password)
        )
        try:
            yield drv
        finally:
            drv.close()


def _load_connection_file(path: Path) -> StackConfig:
    """Build a StackConfig from a single connection file path."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    outputs = data.get("outputs", {})
    password = data["password"]
    browser_url = data["browser_url"]
    host = urlparse(browser_url).hostname or ""

    vm_name = _extract_output(outputs, "vmName")
    data_disk_id = _extract_output(outputs, "dataDiskId")

    # Derive subscription ID from any full resource ID in the outputs.
    vm_id = _extract_output(outputs, "vmId")
    subscription_id = _subscription_from_resource_id(
        vm_id or data_disk_id
    )

    return StackConfig(
        browser_url=browser_url,
        neo4j_uri=data["neo4j_uri"],
        username=data.get("username", "neo4j"),
        password=password,
        host=host,
        resource_group=data.get("resource_group", ""),
        vm_name=vm_name,
        data_disk_id=data_disk_id,
        subscription_id=subscription_id,
    )


def load_from_results(filename: str | None = None) -> StackConfig:
    """Build a StackConfig from a connection file.

    If *filename* is given, load that file from the results directory.
    Otherwise, use the most recent connection file.
    """
    path = _find_connection_file(filename)
    return _load_connection_file(path)


def load_all_from_results() -> list[tuple[str, StackConfig]]:
    """Load all connection files from the results directory.

    Returns a list of (filename, StackConfig) tuples sorted by filename.
    """
    rd = _results_dir()
    matches = sorted(rd.glob("connection-*.json"), key=lambda p: p.name)
    if not matches:
        raise FileNotFoundError(f"No connection files in {rd}")
    return [(p.name, _load_connection_file(p)) for p in matches]


