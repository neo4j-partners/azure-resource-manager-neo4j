"""Azure SDK operations for VM and managed-disk verification.

Follows Azure SDK best practices:
  - Single ``DefaultAzureCredential`` instance, reused across all clients.
  - ``ComputeManagementClient`` used as a context manager to avoid
    connection leaks.
  - ``azure.mgmt.core.tools.parse_resource_id`` for resource ID parsing.
  - Explicit timeout on long-running operations.
"""

import logging
from contextlib import contextmanager
from collections.abc import Generator
from dataclasses import dataclass

from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.core.tools import parse_resource_id

from test_ce.reporting import TestReporter

logger = logging.getLogger(__name__)

# Reuse a single credential instance across the process lifetime.
# DefaultAzureCredential caches tokens internally; recreating it on
# every call wastes time re-discovering the active credential type.
_credential = DefaultAzureCredential()

# Timeout (seconds) for long-running VM operations (restart, etc.).
_LRO_TIMEOUT_SECONDS = 300


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class VmStatus:
    """Snapshot of a VM's provisioning state."""

    name: str
    provisioning_state: str
    location: str


@dataclass(frozen=True)
class DiskStatus:
    """Snapshot of a managed disk's state."""

    name: str
    disk_state: str
    disk_size_gb: int
    sku: str
    zones: tuple[str, ...] = ()
    attached_to_vm: str = ""


# ---------------------------------------------------------------------------
# Client helper
# ---------------------------------------------------------------------------

@contextmanager
def _compute_client(subscription_id: str) -> Generator[ComputeManagementClient, None, None]:
    """Yield a ``ComputeManagementClient`` as a context manager."""
    with ComputeManagementClient(_credential, subscription_id) as client:
        yield client


# ---------------------------------------------------------------------------
# SDK wrappers
# ---------------------------------------------------------------------------

def get_vm_status(
    resource_group: str, vm_name: str, subscription_id: str
) -> VmStatus:
    """Return the provisioning state of a VM."""
    with _compute_client(subscription_id) as client:
        vm = client.virtual_machines.get(resource_group, vm_name)
    return VmStatus(
        name=vm.name,
        provisioning_state=vm.provisioning_state,
        location=vm.location,
    )


def get_disk_status(data_disk_id: str, subscription_id: str) -> DiskStatus:
    """Return the state of a managed disk identified by full resource ID."""
    parsed = parse_resource_id(data_disk_id)
    rg = parsed.get("resource_group", "")
    disk_name = parsed.get("resource_name", "")

    if not rg or not disk_name:
        raise ValueError(
            f"Could not parse resource group or disk name from: {data_disk_id}"
        )

    with _compute_client(subscription_id) as client:
        disk = client.disks.get(rg, disk_name)

    attached_to = ""
    if disk.managed_by:
        attached_parts = parse_resource_id(disk.managed_by)
        attached_to = attached_parts.get("resource_name", "")

    return DiskStatus(
        name=disk.name,
        disk_state=disk.disk_state,
        disk_size_gb=disk.disk_size_gb,
        sku=disk.sku.name if disk.sku else "",
        zones=tuple(disk.zones) if disk.zones else (),
        attached_to_vm=attached_to,
    )


def restart_vm(
    resource_group: str, vm_name: str, subscription_id: str
) -> None:
    """Restart a VM and block until the operation completes."""
    logger.info("Restarting VM %s in %s", vm_name, resource_group)
    with _compute_client(subscription_id) as client:
        poller = client.virtual_machines.begin_restart(resource_group, vm_name)
        poller.result(timeout=_LRO_TIMEOUT_SECONDS)
    logger.info("VM restart completed")


# ---------------------------------------------------------------------------
# Reporter-aware test functions
# ---------------------------------------------------------------------------

def run_azure_checks(
    reporter: TestReporter,
    resource_group: str,
    vm_name: str,
    data_disk_id: str,
    subscription_id: str,
) -> None:
    """Verify VM and disk status, recording results in *reporter*."""
    _check_vm(reporter, resource_group, vm_name, subscription_id)
    _check_disk(reporter, data_disk_id, subscription_id, vm_name)


def _check_vm(
    reporter: TestReporter,
    resource_group: str,
    vm_name: str,
    subscription_id: str,
) -> None:
    with reporter.test("VM Provisioning State") as ctx:
        status = get_vm_status(resource_group, vm_name, subscription_id)
        if status.provisioning_state == "Succeeded":
            ctx.pass_(f"{status.name} Succeeded ({status.location})")
        else:
            ctx.fail(
                f"{status.name} state={status.provisioning_state}"
            )


def _check_disk(
    reporter: TestReporter,
    data_disk_id: str,
    subscription_id: str,
    expected_vm: str,
) -> None:
    with reporter.test("Data Disk Attached") as ctx:
        status = get_disk_status(data_disk_id, subscription_id)
        if status.disk_state != "Attached":
            ctx.fail(f"disk_state={status.disk_state}, expected Attached")
        elif status.attached_to_vm.lower() != expected_vm.lower():
            ctx.fail(
                f"attached to {status.attached_to_vm}, "
                f"expected {expected_vm}"
            )
        else:
            zones = ",".join(status.zones) if status.zones else "none"
            ctx.pass_(
                f"{status.disk_size_gb}GB {status.sku} zone={zones}"
            )
