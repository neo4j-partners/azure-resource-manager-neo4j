"""Status command - show active deployment status."""

import typer
from typing_extensions import Annotated

from ._shared import check_initialized, console


def status(
    verbose: Annotated[
        bool,
        typer.Option("--verbose", "-v", help="Show detailed status information")
    ] = False,
) -> None:
    """
    Show status of active deployments.

    Displays:
    - Deployment ID and name
    - Scenario name
    - Region and resource group
    - Status (pending/deploying/succeeded/failed/deleted)
    - Test status (passed/failed/not-run)
    - Creation time and expiration
    """
    from rich.table import Table

    from ..resource_groups import ResourceGroupManager

    check_initialized()

    # Load all deployment states
    rg_manager = ResourceGroupManager()
    deployments = rg_manager.load_all_deployment_states()

    if not deployments:
        console.print("[yellow]No deployments found[/yellow]")
        console.print("\n[cyan]Deploy a scenario:[/cyan]")
        console.print("  uv run neo4j-deploy deploy --scenario standalone-lts")
        raise typer.Exit(0)

    # Filter out deleted deployments unless verbose
    if not verbose:
        deployments = [d for d in deployments if d.status != "deleted"]

    if not deployments:
        console.print("[yellow]No active deployments[/yellow]")
        console.print("[dim]Use --verbose to see deleted deployments[/dim]")
        raise typer.Exit(0)

    # Create status table
    table = Table(title=f"Deployment Status ({len(deployments)} deployment(s))")
    table.add_column("ID", style="cyan", no_wrap=True)
    table.add_column("Scenario", style="white")
    table.add_column("Resource Group", style="dim")
    table.add_column("Status", style="white")
    table.add_column("Cleanup Mode", style="white")
    table.add_column("Created", style="dim")

    if verbose:
        table.add_column("Branch", style="dim")
        table.add_column("Deployment Name", style="dim")

    # Sort by creation time (newest first)
    deployments_sorted = sorted(deployments, key=lambda d: d.created_at, reverse=True)

    for deployment in deployments_sorted:
        # Format status with color
        status_str = deployment.status
        if deployment.status == "succeeded":
            status_str = f"[green]{deployment.status}[/green]"
        elif deployment.status == "failed":
            status_str = f"[red]{deployment.status}[/red]"
        elif deployment.status == "deleted":
            status_str = f"[dim]{deployment.status}[/dim]"
        elif deployment.status == "deploying":
            status_str = f"[yellow]{deployment.status}[/yellow]"

        # Format deployment ID (show first 8 chars)
        short_id = deployment.deployment_id[:8]

        # Format creation time (relative)
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        age = now - deployment.created_at

        if age.days > 0:
            created_str = f"{age.days}d ago"
        elif age.seconds > 3600:
            created_str = f"{age.seconds // 3600}h ago"
        elif age.seconds > 60:
            created_str = f"{age.seconds // 60}m ago"
        else:
            created_str = "just now"

        # Add row
        row = [
            short_id,
            deployment.scenario_name,
            deployment.resource_group_name,
            status_str,
            deployment.cleanup_mode.value,
            created_str,
        ]

        if verbose:
            row.append(deployment.git_branch)
            row.append(deployment.deployment_name)

        table.add_row(*row)

    console.print(table)

    # Show summary
    console.print()
    active_count = sum(1 for d in deployments if d.status not in ["deleted", "failed"])
    if active_count > 0:
        console.print(f"[cyan]Active deployments:[/cyan] {active_count}")
        console.print("\n[dim]To clean up:[/dim]")
        console.print("  uv run neo4j-deploy cleanup --deployment <id> --force")
        console.print("  uv run neo4j-deploy cleanup --all --force")
