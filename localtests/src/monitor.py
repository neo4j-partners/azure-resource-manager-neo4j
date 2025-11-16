"""
Deployment monitoring and status tracking.

Handles:
- Polling deployment status from Azure
- Live status dashboard with Rich tables
- Timeout detection
- Error extraction and display
"""

import json
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from rich.console import Console
from rich.live import Live
from rich.table import Table

from .models import DeploymentState
from .resource_groups import ResourceGroupManager
from .utils import run_command

console = Console()


class DeploymentMonitor:
    """Monitors Azure deployment status and provides live updates."""

    def __init__(
        self,
        resource_group_manager: ResourceGroupManager,
        poll_interval: int = 30,
        timeout_seconds: int = 1800,
    ) -> None:
        """
        Initialize deployment monitor.

        Args:
            resource_group_manager: Resource group manager instance
            poll_interval: Seconds between status polls (default: 30)
            timeout_seconds: Deployment timeout in seconds (default: 1800 = 30 min)
        """
        self.rg_manager = resource_group_manager
        self.poll_interval = poll_interval
        self.timeout_seconds = timeout_seconds

    def get_deployment_status(
        self,
        resource_group: str,
        deployment_name: str,
    ) -> Optional[str]:
        """
        Get current deployment status from Azure.

        Args:
            resource_group: Resource group name
            deployment_name: Deployment name

        Returns:
            Provisioning state string (Running, Succeeded, Failed, etc.) or None
        """
        try:
            command = (
                f"az deployment group show "
                f"--resource-group {resource_group} "
                f"--name {deployment_name} "
                f"--query properties.provisioningState "
                f"--output tsv"
            )

            result = run_command(command, check=False)

            if result.returncode == 0 and result.stdout:
                status = result.stdout.strip()
                return status
            else:
                return None

        except Exception:
            return None

    def get_deployment_errors(
        self,
        resource_group: str,
        deployment_name: str,
    ) -> list[dict]:
        """
        Extract error details from failed deployment.

        Args:
            resource_group: Resource group name
            deployment_name: Deployment name

        Returns:
            List of error dictionaries with operation details
        """
        try:
            command = (
                f"az deployment operation group list "
                f"--resource-group {resource_group} "
                f"--name {deployment_name} "
                f"--output json"
            )

            result = run_command(command, check=False)

            if result.returncode == 0 and result.stdout:
                operations = json.loads(result.stdout)

                # Filter for failed operations
                errors = []
                for op in operations:
                    if op.get("properties", {}).get("provisioningState") == "Failed":
                        error_info = {
                            "resource": op.get("properties", {}).get("targetResource", {}).get("resourceName", "Unknown"),
                            "resource_type": op.get("properties", {}).get("targetResource", {}).get("resourceType", "Unknown"),
                            "status_code": op.get("properties", {}).get("statusCode", "Unknown"),
                            "status_message": op.get("properties", {}).get("statusMessage", {}).get("error", {}).get("message", "No details available"),
                        }
                        errors.append(error_info)

                return errors
            else:
                return []

        except Exception as e:
            console.print(
                f"[yellow]Warning: Could not extract error details: {e}[/yellow]"
            )
            return []

    def display_deployment_errors(
        self,
        resource_group: str,
        deployment_name: str,
    ) -> None:
        """
        Display deployment errors in a formatted table.

        Args:
            resource_group: Resource group name
            deployment_name: Deployment name
        """
        errors = self.get_deployment_errors(resource_group, deployment_name)

        if not errors:
            console.print(
                "[yellow]No detailed error information available[/yellow]"
            )
            return

        console.print(f"\n[red bold]Deployment Errors for: {deployment_name}[/red bold]\n")

        for i, error in enumerate(errors, 1):
            console.print(f"[red]Error {i}:[/red]")
            console.print(f"  Resource: {error['resource']}")
            console.print(f"  Type: {error['resource_type']}")
            console.print(f"  Status Code: {error['status_code']}")
            console.print(f"  Message: {error['status_message']}")
            console.print()

    def monitor_deployments(
        self,
        deployment_states: list[DeploymentState],
        show_live_dashboard: bool = True,
    ) -> dict[str, str]:
        """
        Monitor multiple deployments until completion or timeout.

        Args:
            deployment_states: List of deployment states to monitor
            show_live_dashboard: If True, show live updating dashboard

        Returns:
            Dictionary mapping deployment_id to final status
        """
        console.print(
            f"[cyan]Monitoring {len(deployment_states)} deployment(s)...[/cyan]\n"
        )

        # Track start times
        start_times = {
            state.deployment_id: datetime.now(timezone.utc)
            for state in deployment_states
        }

        # Track which deployments are still running
        active_deployments = {state.deployment_id: state for state in deployment_states}
        final_statuses = {}

        if show_live_dashboard:
            # Monitor with live dashboard
            with Live(self._generate_status_table(active_deployments, start_times), refresh_per_second=1) as live:
                while active_deployments:
                    # Poll each active deployment
                    for deployment_id in list(active_deployments.keys()):
                        state = active_deployments[deployment_id]

                        # Check timeout
                        elapsed = (datetime.now(timezone.utc) - start_times[deployment_id]).total_seconds()
                        if elapsed > self.timeout_seconds:
                            console.print(
                                f"\n[red]✗ Deployment timed out: {state.deployment_name}[/red]"
                            )
                            self.rg_manager.update_deployment_status(deployment_id, "failed")
                            final_statuses[deployment_id] = "Timeout"
                            del active_deployments[deployment_id]
                            continue

                        # Get current status
                        status = self.get_deployment_status(
                            state.resource_group_name,
                            state.deployment_name
                        )

                        if status in ["Succeeded", "Failed", "Canceled"]:
                            # Deployment completed
                            self.rg_manager.update_deployment_status(
                                deployment_id,
                                "succeeded" if status == "Succeeded" else "failed"
                            )

                            if status == "Succeeded":
                                console.print(
                                    f"\n[green]✓ Deployment succeeded: {state.deployment_name}[/green]"
                                )
                            elif status == "Failed":
                                console.print(
                                    f"\n[red]✗ Deployment failed: {state.deployment_name}[/red]"
                                )
                                self.display_deployment_errors(
                                    state.resource_group_name,
                                    state.deployment_name
                                )
                            else:
                                console.print(
                                    f"\n[yellow]⚠ Deployment canceled: {state.deployment_name}[/yellow]"
                                )

                            final_statuses[deployment_id] = status
                            del active_deployments[deployment_id]

                    # Update live dashboard
                    if active_deployments:
                        live.update(self._generate_status_table(active_deployments, start_times))
                        time.sleep(self.poll_interval)

        else:
            # Monitor without live dashboard (simple polling)
            while active_deployments:
                for deployment_id in list(active_deployments.keys()):
                    state = active_deployments[deployment_id]

                    # Check timeout
                    elapsed = (datetime.now(timezone.utc) - start_times[deployment_id]).total_seconds()
                    if elapsed > self.timeout_seconds:
                        console.print(
                            f"[red]✗ Deployment timed out: {state.deployment_name}[/red]"
                        )
                        self.rg_manager.update_deployment_status(deployment_id, "failed")
                        final_statuses[deployment_id] = "Timeout"
                        del active_deployments[deployment_id]
                        continue

                    # Get current status
                    status = self.get_deployment_status(
                        state.resource_group_name,
                        state.deployment_name
                    )

                    if status in ["Succeeded", "Failed", "Canceled"]:
                        self.rg_manager.update_deployment_status(
                            deployment_id,
                            "succeeded" if status == "Succeeded" else "failed"
                        )

                        if status == "Succeeded":
                            console.print(
                                f"[green]✓ Deployment succeeded: {state.deployment_name}[/green]"
                            )
                        elif status == "Failed":
                            console.print(
                                f"[red]✗ Deployment failed: {state.deployment_name}[/red]"
                            )
                            self.display_deployment_errors(
                                state.resource_group_name,
                                state.deployment_name
                            )

                        final_statuses[deployment_id] = status
                        del active_deployments[deployment_id]

                if active_deployments:
                    time.sleep(self.poll_interval)

        console.print("\n[cyan]All deployments completed[/cyan]")
        return final_statuses

    def _generate_status_table(
        self,
        active_deployments: dict[str, DeploymentState],
        start_times: dict[str, datetime],
    ) -> Table:
        """
        Generate Rich table showing deployment status.

        Args:
            active_deployments: Dictionary of active deployment states
            start_times: Dictionary of deployment start times

        Returns:
            Rich Table object
        """
        table = Table(title="Deployment Status", show_header=True, header_style="bold cyan")
        table.add_column("Scenario", style="white")
        table.add_column("Resource Group", style="dim")
        table.add_column("Status", style="yellow")
        table.add_column("Duration", style="blue")

        for deployment_id, state in active_deployments.items():
            # Get current status
            status = self.get_deployment_status(
                state.resource_group_name,
                state.deployment_name
            ) or "Unknown"

            # Calculate duration
            start_time = start_times[deployment_id]
            elapsed = datetime.now(timezone.utc) - start_time
            duration_str = self._format_duration(elapsed)

            # Color code status
            if status == "Running":
                status_display = f"[yellow]{status}[/yellow]"
            elif status == "Succeeded":
                status_display = f"[green]{status}[/green]"
            elif status == "Failed":
                status_display = f"[red]{status}[/red]"
            else:
                status_display = status

            table.add_row(
                state.scenario_name,
                state.resource_group_name,
                status_display,
                duration_str
            )

        return table

    def _format_duration(self, duration: timedelta) -> str:
        """
        Format timedelta as human-readable duration string.

        Args:
            duration: Time duration

        Returns:
            Formatted string (e.g., "5m 23s")
        """
        total_seconds = int(duration.total_seconds())
        minutes, seconds = divmod(total_seconds, 60)
        hours, minutes = divmod(minutes, 60)

        if hours > 0:
            return f"{hours}h {minutes}m {seconds}s"
        elif minutes > 0:
            return f"{minutes}m {seconds}s"
        else:
            return f"{seconds}s"
