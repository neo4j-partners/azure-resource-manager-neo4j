"""
Resource group lifecycle management.

Handles creation, tagging, tracking, and cleanup of Azure resource groups
used for Neo4j Azure deployments.
"""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field
from rich.console import Console

from .constants import STATE_DIR
from .models import CleanupMode, DeploymentState
from .utils import ensure_directory, get_timestamp, load_json, run_command, save_json

console = Console()


class ResourceGroupManager:
    """Manages Azure resource group lifecycle."""

    def __init__(self) -> None:
        """Initialize the resource group manager."""
        self.state_file = STATE_DIR / "active-deployments.json"
        ensure_directory(STATE_DIR)

    def create_resource_group(
        self,
        name: str,
        location: str,
        tags: Optional[dict[str, str]] = None,
    ) -> bool:
        """
        Create Azure resource group.

        Args:
            name: Resource group name
            location: Azure region
            tags: Optional tags dictionary

        Returns:
            True if creation succeeded, False otherwise
        """
        console.print(f"[cyan]Creating resource group: {name}[/cyan]")

        try:
            # Build tag arguments
            tag_args = ""
            if tags:
                tag_pairs = [f"{k}={v}" for k, v in tags.items()]
                tag_args = f"--tags {' '.join(tag_pairs)}"

            # Create resource group
            result = run_command(
                f"az group create "
                f"--name {name} "
                f"--location {location} "
                f"{tag_args} "
                f"--output json",
                check=False,
            )

            if result.returncode == 0:
                console.print(f"[green]✓ Resource group created: {name}[/green]")
                return True
            else:
                console.print(
                    f"[red]✗ Failed to create resource group: {result.stderr}[/red]"
                )
                return False

        except Exception as e:
            console.print(f"[red]✗ Error creating resource group: {e}[/red]")
            return False

    def delete_resource_group(
        self,
        name: str,
        no_wait: bool = True,
    ) -> bool:
        """
        Delete Azure resource group.

        Args:
            name: Resource group name
            no_wait: If True, don't wait for deletion to complete

        Returns:
            True if deletion started successfully, False otherwise
        """
        console.print(f"[yellow]Deleting resource group: {name}[/yellow]")

        try:
            wait_arg = "--no-wait" if no_wait else ""

            result = run_command(
                f"az group delete "
                f"--name {name} "
                f"--yes "
                f"{wait_arg}",
                check=False,
            )

            if result.returncode == 0:
                if no_wait:
                    console.print(
                        f"[green]✓ Resource group deletion started: {name}[/green]"
                    )
                else:
                    console.print(
                        f"[green]✓ Resource group deleted: {name}[/green]"
                    )
                return True
            else:
                console.print(
                    f"[red]✗ Failed to delete resource group: {result.stderr}[/red]"
                )
                return False

        except Exception as e:
            console.print(f"[red]✗ Error deleting resource group: {e}[/red]")
            return False

    def resource_group_exists(self, name: str) -> bool:
        """
        Check if resource group exists.

        Args:
            name: Resource group name

        Returns:
            True if resource group exists, False otherwise
        """
        try:
            result = run_command(
                f"az group exists --name {name}",
                check=False,
            )

            if result.returncode == 0:
                # Output is "true" or "false" as string
                return result.stdout.strip().lower() == "true"

            return False

        except Exception:
            return False

    def generate_tags(
        self,
        scenario_name: str,
        deployment_id: str,
        branch: str,
        owner_email: str,
        cleanup_mode: CleanupMode,
        expires_hours: int = 24,
    ) -> dict[str, str]:
        """
        Generate standardized tags for resource group.

        Args:
            scenario_name: Test scenario name
            deployment_id: Unique deployment ID
            branch: Git branch name
            owner_email: Owner email address
            cleanup_mode: Cleanup mode
            expires_hours: Hours until expiration (for scheduled mode)

        Returns:
            Tags dictionary
        """
        now = datetime.now(timezone.utc)
        created = now.isoformat()

        # Calculate expiration based on cleanup mode
        if cleanup_mode == CleanupMode.SCHEDULED:
            expires = (now + timedelta(hours=expires_hours)).isoformat()
        else:
            expires = ""

        tags = {
            "purpose": "arm-template-testing",
            "scenario": scenario_name,
            "branch": branch,
            "created": created,
            "owner": owner_email,
            "deployment-id": deployment_id,
            "managed-by": "neo4j-deploy",
            "cleanup-mode": cleanup_mode.value,
        }

        if expires:
            tags["expires"] = expires

        return tags

    def save_deployment_state(self, state: DeploymentState) -> None:
        """
        Save deployment state to tracking file.

        Args:
            state: Deployment state to save
        """
        # Load existing states
        states = self.load_all_deployment_states()

        # Add or update this deployment
        states = [s for s in states if s.deployment_id != state.deployment_id]
        states.append(state)

        # Save back to file
        ensure_directory(self.state_file.parent)
        data = {
            "deployments": [s.model_dump(mode="json") for s in states]
        }
        save_json(data, self.state_file)

        console.print(
            f"[dim]Saved deployment state: {state.deployment_id}[/dim]"
        )

    def load_all_deployment_states(self) -> list[DeploymentState]:
        """
        Load all deployment states from tracking file.

        Returns:
            List of deployment states
        """
        if not self.state_file.exists():
            return []

        try:
            data = load_json(self.state_file)
            deployments_data = data.get("deployments", [])
            return [DeploymentState(**d) for d in deployments_data]
        except Exception as e:
            console.print(
                f"[yellow]Warning: Could not load deployment states: {e}[/yellow]"
            )
            return []

    def get_deployment_state(self, deployment_id: str) -> Optional[DeploymentState]:
        """
        Get specific deployment state by ID.

        Args:
            deployment_id: Deployment ID to find

        Returns:
            DeploymentState if found, None otherwise
        """
        states = self.load_all_deployment_states()
        for state in states:
            if state.deployment_id == deployment_id:
                return state
        return None

    def update_deployment_status(
        self,
        deployment_id: str,
        status: str,
    ) -> None:
        """
        Update deployment status.

        Args:
            deployment_id: Deployment ID to update
            status: New deployment status
        """
        state = self.get_deployment_state(deployment_id)
        if state:
            state.status = status  # type: ignore
            self.save_deployment_state(state)


    def list_managed_resource_groups(self) -> list[dict[str, Any]]:
        """
        List all resource groups managed by this script.

        Returns:
            List of resource group information dictionaries
        """
        try:
            result = run_command(
                "az group list "
                "--tag managed-by=neo4j-deploy "
                "--output json",
                check=False,
            )

            if result.returncode == 0 and result.stdout:
                groups = json.loads(result.stdout)
                return groups
            else:
                return []

        except Exception as e:
            console.print(
                f"[yellow]Warning: Could not list resource groups: {e}[/yellow]"
            )
            return []

    def find_orphaned_resources(self) -> list[str]:
        """
        Find resource groups in Azure that aren't tracked in state file.

        Returns:
            List of orphaned resource group names
        """
        # Get all managed RGs from Azure
        azure_rgs = self.list_managed_resource_groups()
        azure_rg_names = {rg["name"] for rg in azure_rgs}

        # Get all tracked RGs from state file
        states = self.load_all_deployment_states()
        tracked_rg_names = {s.resource_group_name for s in states}

        # Find orphans (in Azure but not tracked)
        orphaned = azure_rg_names - tracked_rg_names

        if orphaned:
            console.print(
                f"[yellow]Found {len(orphaned)} orphaned resource group(s)[/yellow]"
            )

        return list(orphaned)

    def find_expired_deployments(self) -> list[DeploymentState]:
        """
        Find deployments that have expired based on tags.

        Returns:
            List of expired deployment states
        """
        states = self.load_all_deployment_states()
        now = datetime.now(timezone.utc)
        expired = []

        for state in states:
            if state.expires_at and state.expires_at < now:
                expired.append(state)

        if expired:
            console.print(
                f"[yellow]Found {len(expired)} expired deployment(s)[/yellow]"
            )

        return expired
