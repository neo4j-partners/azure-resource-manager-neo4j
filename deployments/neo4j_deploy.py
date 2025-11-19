#!/usr/bin/env python3
"""
Neo4j Azure Deployment Tools

Main entry point for the deployment and testing framework.
"""

import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from typing_extensions import Annotated

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from src.config import ConfigManager
from src.setup import SetupWizard

# Create Typer app
app = typer.Typer(
    name="neo4j-deploy",
    help="Neo4j Azure Deployment Tools - Automated deployment and testing framework for Neo4j Enterprise on Azure",
    add_completion=False,
    rich_markup_mode="rich",
)

console = Console()


def check_initialized() -> ConfigManager:
    """
    Check if the deployment tools are initialized.

    Returns:
        ConfigManager instance

    Raises:
        typer.Exit: If not initialized and user declines setup
    """
    config_manager = ConfigManager()

    if not config_manager.is_initialized():
        console.print(
            "[yellow]Deployment tools not initialized. Running setup wizard...[/yellow]\n"
        )
        wizard = SetupWizard()
        success = wizard.run()

        if not success:
            console.print("[red]Setup failed or was cancelled.[/red]")
            raise typer.Exit(1)

    return config_manager


@app.command()
def setup(
    force: Annotated[
        bool,
        typer.Option("--force", "-f", help="Force re-running setup even if already configured")
    ] = False,
) -> None:
    """
    Run the interactive setup wizard to configure the testing environment.

    This will guide you through configuring:
    - Azure subscription and region settings
    - Resource naming conventions
    - Cleanup behavior and cost limits
    - Test scenario configuration
    - Git integration for automatic artifact location
    - Password management strategy
    """
    config_manager = ConfigManager()

    if config_manager.is_initialized() and not force:
        console.print("[yellow]Deployment tools are already configured.[/yellow]")
        if not typer.confirm("Re-run setup wizard?", default=False):
            console.print("[cyan]Setup cancelled.[/cyan]")
            raise typer.Exit(0)

    wizard = SetupWizard()
    success = wizard.run()

    if success:
        raise typer.Exit(0)
    else:
        console.print("[red]Setup failed or was cancelled.[/red]")
        raise typer.Exit(1)


@app.command()
def validate(
    scenario: Annotated[
        Optional[str],
        typer.Option("--scenario", "-s", help="Validate specific scenario")
    ] = None,
    skip_what_if: Annotated[
        bool,
        typer.Option("--skip-what-if", help="Skip what-if analysis (faster)")
    ] = False,
) -> None:
    """
    Validate ARM templates without deploying.

    Performs:
    - JSON schema validation
    - ARM template best practices checks
    - What-if analysis for resource changes
    - Cost estimation

    Requires a placeholder resource group for validation.
    Creates 'arm-validation-temp' if it doesn't exist.
    """
    from pathlib import Path as PathLib

    from src.deployment import DeploymentEngine
    from src.resource_groups import ResourceGroupManager
    from src.validation import CostEstimator, TemplateValidator

    config_manager = check_initialized()

    # Load configuration
    settings = config_manager.load_settings()
    scenarios = config_manager.load_scenarios()

    if not settings or not scenarios:
        console.print("[red]Error: Configuration not loaded. Run setup first.[/red]")
        raise typer.Exit(1)

    # Filter scenarios
    if scenario:
        selected = [s for s in scenarios.scenarios if s.name == scenario]
        if not selected:
            console.print(f"[red]Error: Scenario '{scenario}' not found[/red]")
            raise typer.Exit(1)
        scenarios_to_validate = selected
    else:
        scenarios_to_validate = scenarios.scenarios

    # Initialize components
    base_template_dir = PathLib("../marketplace/neo4j-enterprise").resolve()
    engine = DeploymentEngine(settings, base_template_dir)
    validator = TemplateValidator()
    cost_estimator = CostEstimator()
    rg_manager = ResourceGroupManager()

    # Ensure validation resource group exists
    validation_rg = "arm-validation-temp"
    if not rg_manager.resource_group_exists(validation_rg):
        console.print(f"\n[cyan]Creating validation resource group: {validation_rg}[/cyan]")
        success = rg_manager.create_resource_group(
            validation_rg,
            settings.default_region,
            tags={"purpose": "arm-template-validation", "managed-by": "neo4j-deploy"},
        )
        if not success:
            console.print(
                "[red]Error: Could not create validation resource group[/red]"
            )
            raise typer.Exit(1)

    console.print(f"\n[bold]Validating {len(scenarios_to_validate)} Scenario(s)[/bold]\n")

    all_valid = True

    for s in scenarios_to_validate:
        console.print(f"\n[bold cyan]Scenario: {s.name}[/bold cyan]")
        console.print("=" * 60)

        # Generate parameter file
        try:
            param_file = engine.generate_parameter_file(s)
        except Exception as e:
            console.print(f"[red]✗ Failed to generate parameters: {e}[/red]")
            all_valid = False
            continue

        # Validate template
        validation_result = validator.validate_template(
            validation_rg,
            engine.template_file,
            param_file,
        )

        if not validation_result.is_valid:
            console.print(f"[red]Validation failed: {validation_result.error_message}[/red]")
            all_valid = False
            continue

        # What-if analysis (if not skipped)
        if not skip_what_if:
            what_if_result = validator.what_if_analysis(
                validation_rg,
                engine.template_file,
                param_file,
            )

            if what_if_result.status == "Succeeded":
                validator.display_what_if_results(what_if_result)

        # Cost estimation
        cost_estimate = cost_estimator.estimate_cost(
            node_count=s.node_count,
            vm_size=s.vm_size,
            disk_size=s.disk_size,
            duration_hours=1,
        )

        within_limit = cost_estimator.display_cost_estimate(
            cost_estimate,
            settings.max_cost_per_deployment,
        )

        if not within_limit:
            console.print(
                "[yellow]⚠ Cost exceeds configured limit. "
                "Deployment will require confirmation.[/yellow]"
            )

        console.print()

    # Summary
    console.print("=" * 60)
    if all_valid:
        console.print(f"\n[green]✓ All {len(scenarios_to_validate)} scenario(s) validated successfully[/green]")
    else:
        console.print(f"\n[yellow]⚠ Some scenarios failed validation[/yellow]")
        raise typer.Exit(1)


@app.command()
def deploy(
    scenario: Annotated[
        Optional[str],
        typer.Option("--scenario", "-s", help="Deploy specific scenario by name")
    ] = None,
    all_scenarios: Annotated[
        bool,
        typer.Option("--all", "-a", help="Deploy all configured scenarios")
    ] = False,
    region: Annotated[
        Optional[str],
        typer.Option("--region", "-r", help="Override default Azure region")
    ] = None,
    cleanup_mode: Annotated[
        Optional[str],
        typer.Option("--cleanup-mode", "-c", help="Override cleanup behavior (immediate/on-success/manual/scheduled)")
    ] = None,
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", "-d", help="Preview deployment without executing")
    ] = False,
) -> None:
    """
    Deploy one or more test scenarios to Azure.

    You must specify either --scenario or --all.

    Examples:
        uv run neo4j-deploy deploy --all
        uv run neo4j-deploy deploy --scenario standalone-v5
        uv run neo4j-deploy deploy --scenario cluster-v5 --region eastus2
        uv run neo4j-deploy deploy --all --dry-run
    """
    from pathlib import Path as PathLib
    from rich.table import Table

    from src.deployment import DeploymentEngine
    from src.orchestrator import DeploymentPlanner

    config_manager = check_initialized()

    # Load configuration first to show available scenarios in error messages
    settings = config_manager.load_settings()
    scenarios = config_manager.load_scenarios()

    if not settings or not scenarios:
        console.print("[red]Error: Configuration not loaded. Run setup first.[/red]")
        raise typer.Exit(1)

    if not scenario and not all_scenarios:
        console.print("[red]Error: Must specify either --scenario or --all[/red]")
        console.print("\n[cyan]Available scenarios:[/cyan]")
        for s in scenarios.scenarios:
            console.print(f"  - {s.name}")
        console.print("\n[cyan]Examples:[/cyan]")
        console.print("  uv run neo4j-deploy deploy --scenario standalone-v5")
        console.print("  uv run neo4j-deploy deploy --all")
        raise typer.Exit(1)

    if scenario and all_scenarios:
        console.print("[red]Error: Cannot specify both --scenario and --all[/red]")
        raise typer.Exit(1)

    # Filter scenarios
    if scenario:
        # Find specific scenario
        selected = [s for s in scenarios.scenarios if s.name == scenario]
        if not selected:
            console.print(f"[red]Error: Scenario '{scenario}' not found[/red]")
            console.print("\n[cyan]Available scenarios:[/cyan]")
            for s in scenarios.scenarios:
                console.print(f"  - {s.name}")
            raise typer.Exit(1)
        scenarios_to_deploy = selected
    else:
        scenarios_to_deploy = scenarios.scenarios

    # Initialize deployment engine
    # Assume we're running from deployments/, so marketplace is ../marketplace
    # Detect deployment type from first scenario (all scenarios should have same type in one deployment)
    first_scenario = scenarios_to_deploy[0]
    from src.models import DeploymentType

    if first_scenario.deployment_type == DeploymentType.AKS:
        base_template_dir = PathLib("../marketplace/neo4j-enterprise-aks").resolve()
        deployment_type = "aks"
    else:
        base_template_dir = PathLib("../marketplace/neo4j-enterprise").resolve()
        deployment_type = "vm"

    try:
        engine = DeploymentEngine(settings, base_template_dir, deployment_type=deployment_type)
        planner = DeploymentPlanner(settings.resource_group_prefix)
    except FileNotFoundError as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)

    # Display deployment plan
    console.print(f"\n[bold]Deployment Plan[/bold]\n")

    table = Table(title="Scenarios to Deploy")
    table.add_column("Scenario", style="cyan")
    table.add_column("Type", style="white")
    table.add_column("Nodes", style="white")
    table.add_column("Version", style="white")
    table.add_column("Size", style="white")
    table.add_column("Region", style="green")

    for s in scenarios_to_deploy:
        target_region = region or settings.default_region
        # Display appropriate size based on deployment type
        if s.deployment_type == DeploymentType.AKS:
            size_display = s.user_node_size or "Standard_E4s_v5"
        else:
            size_display = s.vm_size or "Standard_E4s_v5"

        table.add_row(
            s.name,
            s.deployment_type.value,
            str(s.node_count),
            s.graph_database_version,
            size_display,
            target_region,
        )

    console.print(table)
    console.print(f"\n[cyan]Total scenarios:[/cyan] {len(scenarios_to_deploy)}")
    console.print(f"[cyan]Dry run:[/cyan] {dry_run}")

    # Generate parameter files
    console.print(f"\n[bold]Generating Parameter Files[/bold]\n")

    param_files = []
    for s in scenarios_to_deploy:
        try:
            param_file = engine.generate_parameter_file(
                scenario=s,
                region=region,
            )
            param_files.append((s, param_file))

            # Generate resource group and deployment names
            timestamp = param_file.stem.split("-")[-2:]  # Extract timestamp
            timestamp_str = "-".join(timestamp)
            rg_name = planner.generate_resource_group_name(s.name, timestamp_str)
            deploy_name = planner.generate_deployment_name(s.name, timestamp_str)

            console.print(f"  [green]✓[/green] {s.name}")
            console.print(f"    [dim]Resource group: {rg_name}[/dim]")
            console.print(f"    [dim]Deployment: {deploy_name}[/dim]")
            console.print(f"    [dim]Parameters: {param_file}[/dim]\n")

        except Exception as e:
            console.print(f"  [red]✗[/red] {s.name}: {e}")
            raise typer.Exit(1)

    console.print(f"\n[green]✓ Generated {len(param_files)} parameter file(s)[/green]")

    if dry_run:
        console.print("\n[yellow]Dry run complete. No resources deployed.[/yellow]")
        console.print("[dim]Remove --dry-run to execute deployment[/dim]")
        return

    # Execute actual deployments
    import uuid
    from datetime import datetime, timedelta, timezone

    from src.cleanup import CleanupManager
    from src.models import CleanupMode, DeploymentState
    from src.monitor import DeploymentMonitor
    from src.orchestrator import DeploymentOrchestrator
    from src.password import PasswordManager
    from src.resource_groups import ResourceGroupManager
    from src.utils import get_git_branch

    # Initialize components
    rg_manager = ResourceGroupManager()
    password_manager = PasswordManager(settings)
    orchestrator = DeploymentOrchestrator(
        template_file=engine.template_file,
        resource_group_manager=rg_manager,
    )
    monitor = DeploymentMonitor(
        resource_group_manager=rg_manager,
        poll_interval=30,
        timeout_seconds=settings.deployment_timeout,
    )
    cleanup_manager = CleanupManager(rg_manager)

    # Determine cleanup mode
    if cleanup_mode:
        try:
            cleanup = CleanupMode(cleanup_mode)
        except ValueError:
            console.print(f"[red]Error: Invalid cleanup mode '{cleanup_mode}'[/red]")
            console.print("[cyan]Valid modes: immediate, on-success, manual, scheduled[/cyan]")
            raise typer.Exit(1)
    else:
        cleanup = settings.default_cleanup_mode

    # Get current git branch for tagging
    git_branch = get_git_branch() or "unknown"

    # Create deployments
    console.print(f"\n[bold]Creating Resource Groups and Submitting Deployments[/bold]\n")

    deployment_states = []

    for s, param_file in param_files:
        # Extract timestamp from parameter file name
        timestamp_parts = param_file.stem.split("-")[-2:]
        timestamp_str = "-".join(timestamp_parts)

        # Generate names
        rg_name = planner.generate_resource_group_name(s.name, timestamp_str)
        deploy_name = planner.generate_deployment_name(s.name, timestamp_str)
        deployment_id = str(uuid.uuid4())

        # Create resource group
        target_region = region or settings.default_region
        tags = rg_manager.generate_tags(
            scenario_name=s.name,
            deployment_id=deployment_id,
            branch=git_branch,
            owner_email=settings.owner_email,
            cleanup_mode=cleanup,
            expires_hours=24,
        )

        console.print(f"[cyan]Creating resource group for {s.name}...[/cyan]")
        if not rg_manager.create_resource_group(rg_name, target_region, tags):
            console.print(f"[red]✗ Failed to create resource group for {s.name}[/red]")
            continue

        # Create deployment state
        state = DeploymentState(
            deployment_id=deployment_id,
            resource_group_name=rg_name,
            deployment_name=deploy_name,
            scenario_name=s.name,
            git_branch=git_branch,
            parameter_file_path=str(param_file),
            cleanup_mode=cleanup,
            status="pending",
        )

        # Save initial state
        rg_manager.save_deployment_state(state)

        # Submit deployment
        if orchestrator.submit_deployment(state, param_file, wait=False):
            deployment_states.append(state)
        else:
            console.print(f"[red]✗ Failed to submit deployment for {s.name}[/red]")

    if not deployment_states:
        console.print("\n[red]No deployments were submitted successfully[/red]")
        raise typer.Exit(1)

    console.print(f"\n[green]✓ Submitted {len(deployment_states)} deployment(s)[/green]")

    # Monitor deployments
    console.print(f"\n[bold]Monitoring Deployments[/bold]\n")
    final_statuses = monitor.monitor_deployments(
        deployment_states,
        show_live_dashboard=True,
    )

    # Process completed deployments
    console.print(f"\n[bold]Processing Deployment Outputs[/bold]\n")

    succeeded_count = 0
    failed_count = 0

    for state in deployment_states:
        final_status = final_statuses.get(state.deployment_id)

        if final_status == "Succeeded":
            succeeded_count += 1

            # Extract outputs
            outputs = orchestrator.extract_outputs(
                state.resource_group_name,
                state.deployment_name,
            )

            if outputs:
                # Find scenario for this deployment
                scenario = next((s for s, _ in param_files if s.name == state.scenario_name), None)
                if scenario:
                    # Get password for this scenario
                    password = engine.password_manager.get_password(state.scenario_name)

                    # Parse connection info with credentials
                    conn_info = orchestrator.parse_connection_info(
                        outputs,
                        state,
                        scenario,
                        password,
                    )

                    if conn_info:
                        # Save connection info (includes credentials)
                        orchestrator.save_connection_info(
                            conn_info,
                            state.scenario_name,
                        )
                        console.print(f"[green]✓ Connection info saved for {state.scenario_name}[/green]\n")

                        # Auto-cleanup after successful deployment (if configured)
                        cleanup_manager.auto_cleanup_deployment(state, no_wait=True)
        else:
            failed_count += 1

            # Auto-cleanup for failed deployments (will respect cleanup mode)
            cleanup_manager.auto_cleanup_deployment(state, no_wait=True)

    # Summary
    console.print("\n" + "=" * 60)
    console.print(f"\n[bold]Deployment Summary[/bold]")
    console.print(f"[green]✓ Succeeded:[/green] {succeeded_count}")
    console.print(f"[red]✗ Failed:[/red] {failed_count}")
    console.print(f"[cyan]Total:[/cyan] {len(deployment_states)}")

    if succeeded_count > 0:
        console.print("\n[cyan]Next steps:[/cyan]")

        # Show validation command for each successful deployment
        for state in deployment_states:
            final_status = final_statuses.get(state.deployment_id)
            if final_status == "Succeeded":
                console.print(f"  - Validate {state.scenario_name}: [bold]uv run validate_deploy {state.scenario_name}[/bold]")

        console.print("  - Check status: uv run neo4j-deploy status")

        if cleanup == CleanupMode.MANUAL:
            console.print("  - Clean up resources with: uv run neo4j-deploy cleanup --all")
        else:
            console.print(f"  - Cleanup mode: {cleanup.value} (auto-cleanup {'enabled' if cleanup != CleanupMode.MANUAL else 'disabled'})")

    if failed_count > 0:
        raise typer.Exit(1)


@app.command()
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
    from src.resource_groups import ResourceGroupManager
    from src.validate_deploy import validate_deployment

    config_manager = check_initialized()
    settings = config_manager.load_settings()
    scenarios = config_manager.load_scenarios()

    if not settings or not scenarios:
        console.print("[red]Error: Configuration not loaded. Run setup first.[/red]")
        raise typer.Exit(1)

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
    scenario = next((s for s in scenarios.scenarios if s.name == deployment_state.scenario_name), None)

    if not scenario:
        console.print(f"[red]Error: Scenario '{deployment_state.scenario_name}' not found in configuration[/red]")
        raise typer.Exit(1)

    # Load connection info from .arm-testing/results
    from src.validate_deploy import load_connection_info_from_scenario

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


@app.command()
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
    from src.resource_groups import ResourceGroupManager

    check_initialized()

    # Load all deployment states
    rg_manager = ResourceGroupManager()
    deployments = rg_manager.load_all_deployment_states()

    if not deployments:
        console.print("[yellow]No deployments found[/yellow]")
        console.print("\n[cyan]Deploy a scenario:[/cyan]")
        console.print("  uv run neo4j-deploy deploy --scenario standalone-v5")
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


@app.command()
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
    from src.cleanup import CleanupManager
    from src.resource_groups import ResourceGroupManager

    config_manager = check_initialized()

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

    # If cleaning up all deployments, also delete the Key Vault resource group
    if all_deployments:
        settings = config_manager.load_settings()
        vault_rg = f"{settings.resource_group_prefix}-keyvault"

        console.print(f"\n[cyan]Checking for Key Vault resource group: {vault_rg}[/cyan]")

        if not dry_run:
            from src.utils import run_command

            try:
                # Check if resource group exists
                result = run_command(f"az group show --name {vault_rg} --query id -o tsv")
                if result.stdout.strip():
                    console.print(f"[yellow]Deleting Key Vault resource group: {vault_rg}[/yellow]")
                    run_command(f"az group delete --name {vault_rg} --yes --no-wait")
                    console.print(f"[green]✓ Key Vault resource group deletion initiated[/green]")
            except Exception:
                # Resource group doesn't exist, skip
                console.print(f"[dim]Key Vault resource group not found, skipping[/dim]")
        else:
            console.print(f"[dim]Would delete Key Vault resource group: {vault_rg}[/dim]")

    # Display summary
    cleanup_manager.display_cleanup_summary(summary, dry_run=dry_run)

    # Exit with error if any failed
    if summary.failed > 0:
        raise typer.Exit(1)


@app.command()
def report(
    deployment_id: Annotated[
        Optional[str],
        typer.Argument(help="Deployment ID to generate report for (optional)")
    ] = None,
    output: Annotated[
        Optional[Path],
        typer.Option("--output", "-o", help="Output file path (default: .arm-testing/results/)")
    ] = None,
    format: Annotated[
        str,
        typer.Option("--format", "-f", help="Report format (json/yaml/markdown)")
    ] = "markdown",
) -> None:
    """
    Generate test report for deployments.

    If no deployment_id specified, generates a summary report of all deployments.

    Examples:
        uv run neo4j-deploy report
        uv run neo4j-deploy report abc123
        uv run neo4j-deploy report --format json --output report.json
    """
    check_initialized()
    console.print("[yellow]Report command not yet implemented[/yellow]")

    if deployment_id:
        console.print(f"[cyan]Would generate report for:[/cyan] {deployment_id}")
    else:
        console.print(f"[cyan]Would generate summary report for all deployments[/cyan]")

    console.print(f"[cyan]Format:[/cyan] {format}")
    if output:
        console.print(f"[cyan]Output:[/cyan] {output}")


def main() -> int:
    """
    Main entry point for the CLI.

    Returns:
        Exit code (0 for success, non-zero for error)
    """
    try:
        app()
        return 0
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted by user[/yellow]")
        return 130
    except Exception as e:
        console.print(f"\n[red]Error: {e}[/red]")
        import traceback
        console.print(traceback.format_exc())
        return 1


if __name__ == "__main__":
    sys.exit(main())
