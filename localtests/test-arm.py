#!/usr/bin/env python3
"""
Neo4j ARM Template Testing Suite

Main entry point for the testing framework.
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
    name="test-arm",
    help="Neo4j ARM Template Testing Suite - Automated testing framework for Neo4j Enterprise ARM templates",
    add_completion=False,
    rich_markup_mode="rich",
)

console = Console()


def check_initialized() -> ConfigManager:
    """
    Check if the testing suite is initialized.

    Returns:
        ConfigManager instance

    Raises:
        typer.Exit: If not initialized and user declines setup
    """
    config_manager = ConfigManager()

    if not config_manager.is_initialized():
        console.print(
            "[yellow]Testing suite not initialized. Running setup wizard...[/yellow]\n"
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
        console.print("[yellow]Testing suite is already configured.[/yellow]")
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
            tags={"purpose": "arm-template-validation", "managed-by": "test-arm-script"},
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
    parallel: Annotated[
        int,
        typer.Option("--parallel", "-p", help="Maximum concurrent deployments", min=1, max=10)
    ] = 3,
    artifacts_location: Annotated[
        Optional[str],
        typer.Option("--artifacts-location", help="Override Git-detected artifacts URL")
    ] = None,
) -> None:
    """
    Deploy one or more test scenarios to Azure.

    You must specify either --scenario or --all.

    Examples:
        uv run test-arm.py deploy --all
        uv run test-arm.py deploy --scenario standalone-v5
        uv run test-arm.py deploy --scenario cluster-v5 --region eastus2
        uv run test-arm.py deploy --all --dry-run
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
        console.print("  uv run test-arm.py deploy --scenario standalone-v5")
        console.print("  uv run test-arm.py deploy --all")
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
    # Assume we're running from localtests/, so marketplace is ../marketplace
    base_template_dir = PathLib("../marketplace/neo4j-enterprise").resolve()

    try:
        engine = DeploymentEngine(settings, base_template_dir)
        planner = DeploymentPlanner(settings.resource_group_prefix)
    except FileNotFoundError as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)

    # Display deployment plan
    console.print(f"\n[bold]Deployment Plan[/bold]\n")

    table = Table(title="Scenarios to Deploy")
    table.add_column("Scenario", style="cyan")
    table.add_column("Nodes", style="white")
    table.add_column("Version", style="white")
    table.add_column("VM Size", style="white")
    table.add_column("Region", style="green")

    for s in scenarios_to_deploy:
        target_region = region or settings.default_region
        table.add_row(
            s.name,
            str(s.node_count),
            s.graph_database_version,
            s.vm_size,
            target_region,
        )

    console.print(table)
    console.print(f"\n[cyan]Total scenarios:[/cyan] {len(scenarios_to_deploy)}")
    console.print(f"[cyan]Max parallel:[/cyan] {parallel}")
    console.print(f"[cyan]Dry run:[/cyan] {dry_run}")
    if artifacts_location:
        console.print(f"[cyan]Artifacts location:[/cyan] {artifacts_location}")

    # Generate parameter files
    console.print(f"\n[bold]Generating Parameter Files[/bold]\n")

    param_files = []
    for s in scenarios_to_deploy:
        try:
            param_file = engine.generate_parameter_file(
                scenario=s,
                region=region,
                artifacts_location=artifacts_location,
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

    from src.models import CleanupMode, DeploymentState
    from src.monitor import DeploymentMonitor
    from src.orchestrator import DeploymentOrchestrator
    from src.password import PasswordManager
    from src.resource_groups import ResourceGroupManager
    from src.tester import Neo4jTester
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
    tester = Neo4jTester(
        password_manager=password_manager,
        resource_group_manager=rg_manager,
    )

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
                    # Parse connection info
                    conn_info = orchestrator.parse_connection_info(
                        outputs,
                        state,
                        scenario,
                    )

                    if conn_info:
                        # Save connection info
                        orchestrator.save_connection_info(
                            conn_info,
                            state.scenario_name,
                        )

                        # Run post-deployment tests
                        console.print(f"\n[cyan]Running post-deployment tests for {state.scenario_name}...[/cyan]")
                        try:
                            test_result = tester.test_deployment(
                                conn_info=conn_info,
                                scenario_name=state.scenario_name,
                                license_type=scenario.license_type,
                                deployment_id=state.deployment_id,
                            )

                            if test_result.passed:
                                console.print(f"[green]✓ All tests passed for {state.scenario_name}[/green]\n")
                            else:
                                console.print(f"[red]✗ Tests failed for {state.scenario_name}[/red]\n")
                        except Exception as e:
                            console.print(f"[yellow]Warning: Failed to run tests for {state.scenario_name}: {e}[/yellow]\n")
        else:
            failed_count += 1

    # Summary
    console.print("\n" + "=" * 60)
    console.print(f"\n[bold]Deployment Summary[/bold]")
    console.print(f"[green]✓ Succeeded:[/green] {succeeded_count}")
    console.print(f"[red]✗ Failed:[/red] {failed_count}")
    console.print(f"[cyan]Total:[/cyan] {len(deployment_states)}")

    if succeeded_count > 0:
        console.print("\n[cyan]Next steps:[/cyan]")
        console.print("  - Test deployments with: uv run test-arm.py test <deployment-id>")
        console.print("  - Check status with: uv run test-arm.py status")
        console.print("  - Clean up resources with: uv run test-arm.py cleanup")

    if failed_count > 0:
        raise typer.Exit(1)


@app.command()
def test(
    deployment_id: Annotated[
        str,
        typer.Argument(help="Deployment ID to test")
    ],
) -> None:
    """
    Test an existing deployment.

    Connects to the deployed Neo4j instance and runs validation tests:
    - Database connectivity
    - Correct edition (Community/Enterprise/Evaluation)
    - Basic database operations
    - Plugin verification (GDS, Bloom if configured)

    Example:
        uv run test-arm.py test d681f330-499d-4523-ba5b-42e28d2b7d12
    """
    from pathlib import Path as PathLib

    from src.constants import RESULTS_DIR
    from src.password import PasswordManager
    from src.resource_groups import ResourceGroupManager
    from src.tester import Neo4jTester

    config_manager = check_initialized()
    settings = config_manager.load_settings()
    scenarios = config_manager.load_scenarios()

    if not settings or not scenarios:
        console.print("[red]Error: Configuration not loaded. Run setup first.[/red]")
        raise typer.Exit(1)

    # Initialize components
    rg_manager = ResourceGroupManager()
    password_manager = PasswordManager(settings)
    tester = Neo4jTester(
        password_manager=password_manager,
        resource_group_manager=rg_manager,
    )

    console.print(f"[cyan]Testing deployment: {deployment_id}[/cyan]\n")

    # Get deployment state
    deployment_state = rg_manager.get_deployment_state(deployment_id)

    if not deployment_state:
        console.print(f"[red]Error: Deployment {deployment_id} not found[/red]")
        console.print("[yellow]Run 'uv run test-arm.py status' to see available deployments[/yellow]")
        raise typer.Exit(1)

    console.print(f"[dim]Scenario: {deployment_state.scenario_name}[/dim]")
    console.print(f"[dim]Resource Group: {deployment_state.resource_group_name}[/dim]")

    # Find scenario configuration
    scenario = next((s for s in scenarios if s.name == deployment_state.scenario_name), None)

    if not scenario:
        console.print(f"[red]Error: Scenario '{deployment_state.scenario_name}' not found in configuration[/red]")
        raise typer.Exit(1)

    # Load connection info
    conn_info = tester.load_connection_info(PathLib(RESULTS_DIR), deployment_state.scenario_name)

    if not conn_info:
        console.print(f"[red]Error: No connection information found for {deployment_state.scenario_name}[/red]")
        console.print("[yellow]Connection info is created after successful deployment[/yellow]")
        raise typer.Exit(1)

    # Run tests
    console.print("\n[cyan]Executing tests...[/cyan]\n")

    test_result = tester.test_deployment(
        conn_info=conn_info,
        scenario_name=deployment_state.scenario_name,
        license_type=scenario.license_type,
        deployment_id=deployment_id,
    )

    # Display results
    console.print("\n" + "=" * 60)
    console.print(f"\n[bold]Test Results[/bold]\n")

    if test_result.passed:
        console.print(f"[green]✓ All tests PASSED[/green]")
        console.print(f"\n[dim]Log file: {test_result.log_file}[/dim]")
    else:
        console.print(f"[red]✗ Tests FAILED[/red]")
        console.print(f"\n[red]Exit code: {test_result.exit_code}[/red]")
        console.print(f"[red]Output: {test_result.output}[/red]")
        console.print(f"\n[yellow]Log file: {test_result.log_file}[/yellow]")
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
    check_initialized()
    console.print("[yellow]Status command not yet implemented[/yellow]")

    if verbose:
        console.print("[cyan]Verbose mode enabled[/cyan]")


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
) -> None:
    """
    Clean up Azure resources from test deployments.

    Examples:
        uv run test-arm.py cleanup --deployment abc123
        uv run test-arm.py cleanup --all
        uv run test-arm.py cleanup --older-than 24h
        uv run test-arm.py cleanup --all --force
    """
    check_initialized()

    if not deployment and not all_deployments and not older_than:
        console.print("[red]Error: Must specify --deployment, --all, or --older-than[/red]")
        raise typer.Exit(1)

    console.print("[yellow]Cleanup command not yet implemented[/yellow]")

    if deployment:
        console.print(f"[cyan]Would clean up deployment:[/cyan] {deployment}")
    if all_deployments:
        console.print(f"[cyan]Would clean up:[/cyan] All deployments")
    if older_than:
        console.print(f"[cyan]Would clean up deployments older than:[/cyan] {older_than}")
    if force:
        console.print(f"[cyan]Force mode:[/cyan] Skip confirmations")


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
        uv run test-arm.py report
        uv run test-arm.py report abc123
        uv run test-arm.py report --format json --output report.json
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
