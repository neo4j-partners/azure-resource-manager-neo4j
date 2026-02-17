"""Test command - validate a deployed Neo4j instance."""

from typing import Optional

import typer
from typing_extensions import Annotated

from ._shared import console, load_config


def test(
    deployment_id: Annotated[
        Optional[str],
        typer.Argument(help="Deployment ID to test (defaults to most recent successful deployment)")
    ] = None,
) -> None:
    """
    Test an existing deployment using validate_deploy.

    Connects to the deployed Neo4j instance and runs validation tests:
    - Creates test dataset
    - Verifies database connectivity
    - Checks license type
    - Cleans up test data

    If no deployment ID is provided, tests the most recent successful deployment.

    Examples:
        uv run neo4j-deploy test                                       # Test most recent
        uv run neo4j-deploy test d681f330-499d-4523-ba5b-42e28d2b7d12  # Test specific deployment
    """
    from ..resource_groups import ResourceGroupManager
    from ..validate_deploy import validate_deployment

    cfg = load_config()

    # Initialize components
    rg_manager = ResourceGroupManager()

    # If no deployment_id provided, use most recent successful deployment
    if deployment_id is None:
        all_deployments = rg_manager.load_all_deployment_states()

        # Filter for successful deployments and sort by created_at
        successful_deployments = [
            d for d in all_deployments
            if d.status == "succeeded"
        ]

        if not successful_deployments:
            console.print("[red]Error: No successful deployments found.[/red]")
            console.print("[yellow]Deploy first with: uv run neo4j-deploy deploy --scenario <scenario-name>[/yellow]")
            raise typer.Exit(1)

        # Sort by created_at (most recent first)
        successful_deployments.sort(key=lambda d: d.created_at, reverse=True)
        deployment_id = successful_deployments[0].deployment_id

        console.print(f"[dim]Using most recent successful deployment: {deployment_id}[/dim]\n")

    console.print(f"[cyan]Testing deployment: {deployment_id}[/cyan]\n")

    # Get deployment state
    deployment_state = rg_manager.get_deployment_state(deployment_id)

    if not deployment_state:
        console.print(f"[red]Error: Deployment {deployment_id} not found[/red]")
        console.print("[yellow]Run 'uv run neo4j-deploy status' to see available deployments[/yellow]")
        raise typer.Exit(1)

    console.print(f"[dim]Scenario: {deployment_state.scenario_name}[/dim]")
    console.print(f"[dim]Resource Group: {deployment_state.resource_group_name}[/dim]\n")

    # Find scenario configuration
    scenario = next((s for s in cfg.scenarios.scenarios if s.name == deployment_state.scenario_name), None)

    if not scenario:
        console.print(f"[red]Error: Scenario '{deployment_state.scenario_name}' not found in configuration[/red]")
        raise typer.Exit(1)

    # Load connection info from .arm-testing/results
    from ..validate_deploy import load_connection_info_from_scenario

    conn_data = load_connection_info_from_scenario(deployment_state.scenario_name)
    if not conn_data:
        console.print(f"[red]Error: No connection information found for {deployment_state.scenario_name}[/red]")
        console.print("[yellow]Connection info is created after successful deployment[/yellow]")
        raise typer.Exit(1)

    # Extract connection details
    uri = conn_data.get("neo4j_uri")
    username = conn_data.get("username", "neo4j")
    password = conn_data.get("password")

    if not uri or not password:
        console.print("[red]Error: Connection info is incomplete[/red]")
        raise typer.Exit(1)

    # Run validation
    console.print(f"[cyan]Running validation...[/cyan]\n")

    try:
        success = validate_deployment(uri, username, password, scenario.license_type)

        console.print("\n" + "=" * 60)
        console.print(f"\n[bold]Test Results[/bold]\n")

        if success:
            console.print(f"[green]✓ All tests PASSED[/green]")
        else:
            console.print(f"[red]✗ Tests FAILED[/red]")
            raise typer.Exit(1)

    except Exception as e:
        console.print(f"\n[red]✗ Test execution failed: {e}[/red]")
        raise typer.Exit(1)
