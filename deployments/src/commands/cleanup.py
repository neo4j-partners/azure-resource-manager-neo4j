"""Cleanup command - remove Azure resources from test deployments."""

from typing import Optional

import typer
from typing_extensions import Annotated

from ._shared import check_initialized, console


def cleanup(
    deployment: Annotated[
        Optional[str],
        typer.Option("--deployment", "-d", help="Clean up specific deployment by ID")
    ] = None,
    all_deployments: Annotated[
        bool,
        typer.Option("--all", "-a", help="Clean up all resources")
    ] = False,
    older_than: Annotated[
        Optional[str],
        typer.Option("--older-than", "-o", help="Clean up resources older than duration (e.g., '2h', '1d')")
    ] = None,
    force: Annotated[
        bool,
        typer.Option("--force", "-f", help="Skip confirmation prompts")
    ] = False,
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", help="Preview cleanup without executing")
    ] = False,
) -> None:
    """
    Clean up Azure resources from test deployments.

    Cleanup modes:
    - immediate: Delete resources immediately after deployment
    - on-success: Delete only if tests passed (keep failures for debugging)
    - manual: Never auto-delete (requires --force flag)
    - scheduled: Delete when expiration time is reached

    Examples:
        uv run neo4j-deploy cleanup --deployment 2c4ca18c --force
        uv run neo4j-deploy cleanup --all --force
        uv run neo4j-deploy cleanup --older-than 24h
        uv run neo4j-deploy cleanup --all --dry-run
    """
    from ..cleanup import CleanupManager
    from ..resource_groups import ResourceGroupManager

    check_initialized()

    if not deployment and not all_deployments and not older_than:
        console.print("[red]Error: Must specify --deployment, --all, or --older-than[/red]")
        console.print("\n[cyan]Examples:[/cyan]")
        console.print("  uv run neo4j-deploy cleanup --deployment 2c4ca18c --force")
        console.print("  uv run neo4j-deploy cleanup --all --force")
        console.print("  uv run neo4j-deploy cleanup --older-than 24h")
        raise typer.Exit(1)

    # Initialize components
    rg_manager = ResourceGroupManager()
    cleanup_manager = CleanupManager(rg_manager)

    # Load all deployments
    all_states = rg_manager.load_all_deployment_states()

    if not all_states:
        console.print("[yellow]No deployments found in state file[/yellow]")
        raise typer.Exit(0)

    # Filter deployments based on criteria
    deployments_to_cleanup = []

    if deployment:
        # Clean up specific deployment by ID (partial match supported)
        matching = [
            d for d in all_states
            if d.deployment_id.startswith(deployment) or deployment in d.deployment_id
        ]

        if not matching:
            console.print(f"[red]Error: No deployment found matching '{deployment}'[/red]")
            console.print("\n[yellow]Run 'uv run neo4j-deploy status' to see available deployments[/yellow]")
            raise typer.Exit(1)

        if len(matching) > 1:
            console.print(f"[yellow]Warning: Multiple deployments match '{deployment}':[/yellow]")
            for d in matching:
                console.print(f"  - {d.deployment_id} ({d.scenario_name})")
            console.print("\n[yellow]Please provide a more specific deployment ID[/yellow]")
            raise typer.Exit(1)

        deployments_to_cleanup = matching

    elif older_than:
        # Clean up deployments older than specified duration
        filtered = cleanup_manager.filter_deployments_by_age(all_states, older_than)

        if not filtered:
            console.print(f"[yellow]No deployments found older than {older_than}[/yellow]")
            raise typer.Exit(0)

        deployments_to_cleanup = filtered

    elif all_deployments:
        # Clean up all deployments (excluding already deleted)
        deployments_to_cleanup = [
            d for d in all_states
            if d.status != "deleted"
        ]

        if not deployments_to_cleanup:
            console.print("[yellow]No active deployments to clean up[/yellow]")
            raise typer.Exit(0)

    # Execute cleanup
    summary = cleanup_manager.cleanup_deployments(
        deployments=deployments_to_cleanup,
        dry_run=dry_run,
        force=force,
        no_wait=True,
    )

    # Display summary
    cleanup_manager.display_cleanup_summary(summary, dry_run=dry_run)

    # Exit with error if any failed
    if summary.failed > 0:
        raise typer.Exit(1)
