"""
Cleanup orchestration and resource management.

Handles automated and manual cleanup of Azure resources based on
deployment status, test results, and configured cleanup modes.
"""

import re
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional

from pydantic import BaseModel, Field
from rich.console import Console
from rich.table import Table

from .models import CleanupMode, DeploymentState
from .resource_groups import ResourceGroupManager

console = Console()


class CleanupDecision(BaseModel):
    """Decision about whether to clean up a deployment."""

    deployment_id: str = Field(..., description="Deployment ID")
    resource_group_name: str = Field(..., description="Resource group to clean up")
    should_cleanup: bool = Field(..., description="Whether cleanup should proceed")
    reason: str = Field(..., description="Reason for the decision")
    cleanup_mode: CleanupMode = Field(..., description="Cleanup mode that triggered decision")


class CleanupResult(BaseModel):
    """Result of a cleanup operation."""

    deployment_id: str = Field(..., description="Deployment ID")
    resource_group_name: str = Field(..., description="Resource group name")
    success: bool = Field(..., description="Whether cleanup succeeded")
    deleted_at: Optional[datetime] = Field(None, description="Deletion timestamp")
    error_message: Optional[str] = Field(None, description="Error message if failed")


class CleanupSummary(BaseModel):
    """Summary of cleanup operation."""

    total_candidates: int = Field(..., description="Total deployments considered")
    cleaned_up: int = Field(..., description="Successfully cleaned up")
    failed: int = Field(..., description="Failed to clean up")
    skipped: int = Field(..., description="Skipped (based on cleanup rules)")
    results: list[CleanupResult] = Field(default_factory=list, description="Individual results")


class CleanupManager:
    """Manages cleanup of Azure resources from test deployments."""

    def __init__(self, resource_group_manager: ResourceGroupManager) -> None:
        """
        Initialize the cleanup manager.

        Args:
            resource_group_manager: ResourceGroupManager instance for Azure operations
        """
        self.rg_manager = resource_group_manager

    def should_cleanup_deployment(
        self,
        deployment: DeploymentState,
        force_mode: Optional[CleanupMode] = None,
    ) -> CleanupDecision:
        """
        Determine if a deployment should be cleaned up based on its state and cleanup mode.

        Args:
            deployment: Deployment state to evaluate
            force_mode: Optional cleanup mode to override deployment's configured mode

        Returns:
            CleanupDecision with recommendation and reasoning
        """
        mode = force_mode or deployment.cleanup_mode

        # Already deleted - skip
        if deployment.status == "deleted":
            return CleanupDecision(
                deployment_id=deployment.deployment_id,
                resource_group_name=deployment.resource_group_name,
                should_cleanup=False,
                reason="Already deleted",
                cleanup_mode=mode,
            )

        # Manual mode - never auto-cleanup
        if mode == CleanupMode.MANUAL:
            return CleanupDecision(
                deployment_id=deployment.deployment_id,
                resource_group_name=deployment.resource_group_name,
                should_cleanup=False,
                reason="Manual cleanup mode - requires explicit cleanup command",
                cleanup_mode=mode,
            )

        # Immediate mode - always cleanup regardless of status
        if mode == CleanupMode.IMMEDIATE:
            return CleanupDecision(
                deployment_id=deployment.deployment_id,
                resource_group_name=deployment.resource_group_name,
                should_cleanup=True,
                reason="Immediate cleanup mode",
                cleanup_mode=mode,
            )

        # On-success mode - cleanup only if tests passed
        if mode == CleanupMode.ON_SUCCESS:
            if deployment.status == "failed":
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=False,
                    reason="Deployment failed - keeping for debugging",
                    cleanup_mode=mode,
                )

            if deployment.test_status == "failed":
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=False,
                    reason="Tests failed - keeping for debugging",
                    cleanup_mode=mode,
                )

            if deployment.test_status == "not-run" or deployment.test_status is None:
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=False,
                    reason="Tests not run yet - waiting for test results",
                    cleanup_mode=mode,
                )

            if deployment.test_status == "passed":
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=True,
                    reason="Tests passed - safe to cleanup",
                    cleanup_mode=mode,
                )

        # Scheduled mode - cleanup based on expiration
        if mode == CleanupMode.SCHEDULED:
            if deployment.expires_at is None:
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=False,
                    reason="No expiration time set",
                    cleanup_mode=mode,
                )

            now = datetime.now(timezone.utc)
            if deployment.expires_at <= now:
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=True,
                    reason=f"Expired at {deployment.expires_at.isoformat()}",
                    cleanup_mode=mode,
                )
            else:
                time_remaining = deployment.expires_at - now
                hours_remaining = time_remaining.total_seconds() / 3600
                return CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=False,
                    reason=f"Not expired yet ({hours_remaining:.1f} hours remaining)",
                    cleanup_mode=mode,
                )

        # Default: don't cleanup
        return CleanupDecision(
            deployment_id=deployment.deployment_id,
            resource_group_name=deployment.resource_group_name,
            should_cleanup=False,
            reason="Unknown cleanup mode",
            cleanup_mode=mode,
        )

    def cleanup_deployment(
        self,
        deployment: DeploymentState,
        dry_run: bool = False,
        no_wait: bool = True,
        force: bool = False,
    ) -> CleanupResult:
        """
        Clean up a single deployment by deleting its resource group.

        Args:
            deployment: Deployment to clean up
            dry_run: If True, only simulate cleanup without actually deleting
            no_wait: If True, don't wait for deletion to complete
            force: If True, bypass safety checks (use with caution!)

        Returns:
            CleanupResult with operation status
        """
        rg_name = deployment.resource_group_name

        if dry_run:
            console.print(f"[dim][DRY RUN] Would delete resource group: {rg_name}[/dim]")
            return CleanupResult(
                deployment_id=deployment.deployment_id,
                resource_group_name=rg_name,
                success=True,
                deleted_at=None,
                error_message=None,
            )

        # Safety check: verify resource group has managed-by tag (skip if force=True)
        if not force and not self._verify_managed_resource_group(rg_name):
            error_msg = (
                f"Resource group {rg_name} is not managed by neo4j-deploy. "
                f"Refusing to delete for safety. Use --force to override."
            )
            console.print(f"[red]✗ {error_msg}[/red]")
            return CleanupResult(
                deployment_id=deployment.deployment_id,
                resource_group_name=rg_name,
                success=False,
                deleted_at=None,
                error_message=error_msg,
            )

        # Show warning if force bypassing safety check
        if force and not self._verify_managed_resource_group(rg_name):
            console.print(
                f"[yellow]⚠ Warning: Force deleting unmanaged resource group: {rg_name}[/yellow]"
            )

        # Delete resource group
        success = self.rg_manager.delete_resource_group(rg_name, no_wait=no_wait)

        if success:
            # Update state to mark as deleted
            deployment.status = "deleted"  # type: ignore
            self.rg_manager.save_deployment_state(deployment)

            return CleanupResult(
                deployment_id=deployment.deployment_id,
                resource_group_name=rg_name,
                success=True,
                deleted_at=datetime.now(timezone.utc),
                error_message=None,
            )
        else:
            return CleanupResult(
                deployment_id=deployment.deployment_id,
                resource_group_name=rg_name,
                success=False,
                deleted_at=None,
                error_message="Failed to delete resource group",
            )

    def _verify_managed_resource_group(self, rg_name: str) -> bool:
        """
        Verify that a resource group is managed by this script.

        Args:
            rg_name: Resource group name to check

        Returns:
            True if resource group has managed-by tag, False otherwise
        """
        managed_rgs = self.rg_manager.list_managed_resource_groups()
        return any(rg["name"] == rg_name for rg in managed_rgs)

    def parse_age_duration(self, duration_str: str) -> Optional[timedelta]:
        """
        Parse a duration string like '2h', '3d', '30m' into timedelta.

        Args:
            duration_str: Duration string (e.g., '2h', '3d', '30m', '1w')

        Returns:
            timedelta object or None if parsing fails
        """
        pattern = r'^(\d+)([mhdw])$'
        match = re.match(pattern, duration_str.lower())

        if not match:
            return None

        value = int(match.group(1))
        unit = match.group(2)

        if unit == 'm':
            return timedelta(minutes=value)
        elif unit == 'h':
            return timedelta(hours=value)
        elif unit == 'd':
            return timedelta(days=value)
        elif unit == 'w':
            return timedelta(weeks=value)

        return None

    def filter_deployments_by_age(
        self,
        deployments: list[DeploymentState],
        older_than: str,
    ) -> list[DeploymentState]:
        """
        Filter deployments older than specified duration.

        Args:
            deployments: List of deployments to filter
            older_than: Duration string (e.g., '2h', '3d')

        Returns:
            Filtered list of deployments
        """
        duration = self.parse_age_duration(older_than)

        if duration is None:
            console.print(f"[yellow]Warning: Could not parse duration '{older_than}'[/yellow]")
            console.print("[yellow]Expected format: <number><unit> (e.g., '2h', '3d', '30m', '1w')[/yellow]")
            return []

        now = datetime.now(timezone.utc)
        cutoff_time = now - duration

        filtered = [
            d for d in deployments
            if d.created_at and d.created_at < cutoff_time
        ]

        console.print(
            f"[dim]Found {len(filtered)} deployment(s) older than {older_than}[/dim]"
        )

        return filtered

    def cleanup_deployments(
        self,
        deployments: list[DeploymentState],
        dry_run: bool = False,
        force: bool = False,
        no_wait: bool = True,
    ) -> CleanupSummary:
        """
        Clean up multiple deployments.

        Args:
            deployments: List of deployments to clean up
            dry_run: If True, simulate cleanup without deleting
            force: If True, skip cleanup decision logic and delete all
            no_wait: If True, don't wait for deletion to complete

        Returns:
            CleanupSummary with results
        """
        if not deployments:
            console.print("[yellow]No deployments to clean up[/yellow]")
            return CleanupSummary(
                total_candidates=0,
                cleaned_up=0,
                failed=0,
                skipped=0,
            )

        console.print(f"\n[bold]Evaluating {len(deployments)} Deployment(s)[/bold]\n")

        # Evaluate cleanup decisions
        decisions = []
        for deployment in deployments:
            if force:
                # Force mode: cleanup everything
                decision = CleanupDecision(
                    deployment_id=deployment.deployment_id,
                    resource_group_name=deployment.resource_group_name,
                    should_cleanup=True,
                    reason="Force flag specified",
                    cleanup_mode=deployment.cleanup_mode,
                )
            else:
                decision = self.should_cleanup_deployment(deployment)

            decisions.append((deployment, decision))

        # Display decisions
        table = Table(title="Cleanup Plan")
        table.add_column("Deployment ID", style="cyan", no_wrap=True, max_width=30)
        table.add_column("Resource Group", style="white", no_wrap=True)
        table.add_column("Action", style="white")
        table.add_column("Reason", style="dim")

        for deployment, decision in decisions:
            action = "[green]DELETE[/green]" if decision.should_cleanup else "[dim]SKIP[/dim]"
            # Truncate deployment ID for display
            short_id = deployment.deployment_id[:8] + "..."
            table.add_row(
                short_id,
                deployment.resource_group_name,
                action,
                decision.reason,
            )

        console.print(table)

        # Filter to only those that should be cleaned up
        to_cleanup = [
            (deployment, decision)
            for deployment, decision in decisions
            if decision.should_cleanup
        ]

        if not to_cleanup:
            console.print("\n[yellow]No deployments meet cleanup criteria[/yellow]")
            return CleanupSummary(
                total_candidates=len(deployments),
                cleaned_up=0,
                failed=0,
                skipped=len(deployments),
            )

        console.print(f"\n[yellow]Will clean up {len(to_cleanup)} deployment(s)[/yellow]")

        # Confirm unless force or dry_run
        if not force and not dry_run:
            from rich.prompt import Confirm

            if not Confirm.ask("\nProceed with cleanup?", default=False):
                console.print("[cyan]Cleanup cancelled[/cyan]")
                return CleanupSummary(
                    total_candidates=len(deployments),
                    cleaned_up=0,
                    failed=0,
                    skipped=len(deployments),
                )

        # Execute cleanup
        console.print(f"\n[bold]Executing Cleanup[/bold]\n")

        results = []
        for deployment, decision in to_cleanup:
            result = self.cleanup_deployment(
                deployment,
                dry_run=dry_run,
                no_wait=no_wait,
                force=force,
            )
            results.append(result)

            if result.success:
                if dry_run:
                    console.print(f"[dim]✓ [DRY RUN] {result.resource_group_name}[/dim]")
                else:
                    console.print(f"[green]✓ Deleted: {result.resource_group_name}[/green]")
            else:
                console.print(f"[red]✗ Failed: {result.resource_group_name}[/red]")
                if result.error_message:
                    console.print(f"[red]  {result.error_message}[/red]")

        # Build summary
        cleaned_up = sum(1 for r in results if r.success)
        failed = sum(1 for r in results if not r.success)
        skipped = len(deployments) - len(to_cleanup)

        return CleanupSummary(
            total_candidates=len(deployments),
            cleaned_up=cleaned_up,
            failed=failed,
            skipped=skipped,
            results=results,
        )

    def display_cleanup_summary(self, summary: CleanupSummary, dry_run: bool = False) -> None:
        """
        Display cleanup summary.

        Args:
            summary: Cleanup summary to display
            dry_run: Whether this was a dry run
        """
        console.print("\n" + "=" * 60)
        console.print(f"\n[bold]Cleanup Summary{'(Dry Run)' if dry_run else ''}[/bold]\n")

        console.print(f"[cyan]Total evaluated:[/cyan] {summary.total_candidates}")
        console.print(f"[green]Cleaned up:[/green] {summary.cleaned_up}")
        console.print(f"[red]Failed:[/red] {summary.failed}")
        console.print(f"[dim]Skipped:[/dim] {summary.skipped}")

        if dry_run and summary.cleaned_up > 0:
            console.print(f"\n[yellow]This was a dry run. No resources were actually deleted.[/yellow]")
            console.print(f"[yellow]Run without --dry-run to execute cleanup.[/yellow]")

    def auto_cleanup_deployment(
        self,
        deployment: DeploymentState,
        no_wait: bool = True,
    ) -> Optional[CleanupResult]:
        """
        Automatically clean up a deployment based on its cleanup mode.

        This is called after deployment/testing completes to perform automatic cleanup.

        Args:
            deployment: Deployment to potentially clean up
            no_wait: If True, don't wait for deletion to complete

        Returns:
            CleanupResult if cleanup was performed, None if skipped
        """
        decision = self.should_cleanup_deployment(deployment)

        if not decision.should_cleanup:
            console.print(f"[dim]Cleanup decision: {decision.reason}[/dim]")
            return None

        console.print(f"\n[yellow]Auto-cleanup triggered: {decision.reason}[/yellow]")

        result = self.cleanup_deployment(deployment, dry_run=False, no_wait=no_wait)

        if result.success:
            console.print(f"[green]✓ Auto-cleanup completed for {deployment.scenario_name}[/green]")
        else:
            console.print(f"[red]✗ Auto-cleanup failed for {deployment.scenario_name}[/red]")

        return result
