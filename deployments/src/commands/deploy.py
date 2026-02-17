"""Deploy command - deploy test scenarios to Azure."""

from typing import Optional

import typer
from typing_extensions import Annotated

from ._shared import console, load_config


def deploy(
    scenario: Annotated[
        Optional[str],
        typer.Option("--scenario", "-s", help="Deploy specific scenario by name")
    ] = None,
    all_scenarios: Annotated[
        bool,
        typer.Option("--all", "-a", help="Deploy all configured scenarios")
    ] = False,
    cleanup_mode: Annotated[
        Optional[str],
        typer.Option("--cleanup-mode", "-c", help="Override cleanup behavior (immediate/on-success/manual/scheduled)")
    ] = None,
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", "-d", help="Preview deployment without executing")
    ] = False,
    debug: Annotated[
        bool,
        typer.Option("--debug", help="Enable debug mode with verbose Neo4j logging")
    ] = False,
) -> None:
    """
    Deploy one or more test scenarios to Azure.

    You must specify either --scenario or --all.

    Examples:
        uv run neo4j-deploy deploy --all
        uv run neo4j-deploy deploy --scenario standalone-lts
        uv run neo4j-deploy deploy --all --dry-run
    """
    from rich.table import Table

    from ..deployment import DeploymentEngine, get_template_dir
    from ..models import PreparedScenario, ScenarioDeployment
    from ..orchestrator import DeploymentPlanner

    cfg = load_config()

    if not scenario and not all_scenarios:
        console.print("[red]Error: Must specify either --scenario or --all[/red]")
        console.print("\n[cyan]Available scenarios:[/cyan]")
        for s in cfg.scenarios.scenarios:
            console.print(f"  - {s.name}")
        console.print("\n[cyan]Examples:[/cyan]")
        console.print("  uv run neo4j-deploy deploy --scenario standalone-lts")
        console.print("  uv run neo4j-deploy deploy --all")
        raise typer.Exit(1)

    if scenario and all_scenarios:
        console.print("[red]Error: Cannot specify both --scenario and --all[/red]")
        raise typer.Exit(1)

    # Filter scenarios
    if scenario:
        # Find specific scenario
        selected = [s for s in cfg.scenarios.scenarios if s.name == scenario]
        if not selected:
            console.print(f"[red]Error: Scenario '{scenario}' not found[/red]")
            console.print("\n[cyan]Available scenarios:[/cyan]")
            for s in cfg.scenarios.scenarios:
                console.print(f"  - {s.name}")
            raise typer.Exit(1)
        scenarios_to_deploy = selected
    else:
        scenarios_to_deploy = cfg.scenarios.scenarios

    # Initialize planner (shared across scenarios)
    planner = DeploymentPlanner(cfg.settings.resource_group_prefix)

    # Display deployment plan
    console.print(f"\n[bold]Deployment Plan[/bold]\n")

    table = Table(title="Scenarios to Deploy")
    table.add_column("Scenario", style="cyan")
    table.add_column("Edition", style="white")
    table.add_column("Type", style="white")
    table.add_column("Nodes", style="white")
    table.add_column("Version", style="white")
    table.add_column("Size", style="white")
    table.add_column("Region", style="green")

    for s in scenarios_to_deploy:
        target_region = s.region or cfg.settings.default_region
        size_display = s.vm_size or "Standard_E4s_v5"

        table.add_row(
            s.name,
            s.license_type,
            s.deployment_type.value,
            str(s.node_count),
            s.graph_database_version,
            size_display,
            target_region,
        )

    console.print(table)
    console.print(f"\n[cyan]Total scenarios:[/cyan] {len(scenarios_to_deploy)}")
    console.print(f"[cyan]Dry run:[/cyan] {dry_run}")
    if debug:
        console.print(f"[yellow]Debug mode:[/yellow] ENABLED - Verbose Neo4j logging will be configured")

    # Generate parameter files (engine created per-scenario based on edition)
    console.print(f"\n[bold]Generating Parameter Files[/bold]\n")

    engines: dict[str, DeploymentEngine] = {}  # Cache by license_type
    prepared: list[PreparedScenario] = []
    for s in scenarios_to_deploy:
        try:
            # Get or create engine for this scenario's edition
            if s.license_type not in engines:
                base_template_dir = get_template_dir(s.license_type)
                engines[s.license_type] = DeploymentEngine(cfg.settings, base_template_dir)
            engine = engines[s.license_type]

            param_file = engine.generate_parameter_file(
                scenario=s,
                debug_mode=debug,
            )
            prepared.append(PreparedScenario(
                scenario=s,
                parameter_file=param_file,
                engine=engine,
            ))

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

    console.print(f"\n[green]✓ Generated {len(prepared)} parameter file(s)[/green]")

    if dry_run:
        console.print("\n[yellow]Dry run complete. No resources deployed.[/yellow]")
        console.print("[dim]Remove --dry-run to execute deployment[/dim]")
        return

    # Execute actual deployments
    _execute_deployments(cfg, prepared, planner, engines, cleanup_mode, debug)


def _execute_deployments(cfg, prepared, planner, engines, cleanup_mode, debug):
    """Execute the actual Azure deployments after parameter generation."""
    import uuid

    from ..cleanup import CleanupManager
    from ..models import CleanupMode, DeploymentState, ScenarioDeployment
    from ..monitor import DeploymentMonitor
    from ..orchestrator import DeploymentOrchestrator
    from ..resource_groups import ResourceGroupManager
    from ..utils import get_git_branch

    # Initialize shared components
    rg_manager = ResourceGroupManager()
    monitor = DeploymentMonitor(
        resource_group_manager=rg_manager,
        poll_interval=30,
        timeout_seconds=cfg.settings.deployment_timeout,
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
        cleanup = cfg.settings.default_cleanup_mode

    # Get current git branch for tagging
    git_branch = get_git_branch() or "unknown"

    # Create deployments
    console.print(f"\n[bold]Creating Resource Groups and Submitting Deployments[/bold]\n")

    deployments: list[ScenarioDeployment] = []

    for prep in prepared:
        # Extract timestamp from parameter file name
        timestamp_parts = prep.parameter_file.stem.split("-")[-2:]
        timestamp_str = "-".join(timestamp_parts)

        # Generate names
        rg_name = planner.generate_resource_group_name(prep.scenario.name, timestamp_str)
        deploy_name = planner.generate_deployment_name(prep.scenario.name, timestamp_str)
        deployment_id = str(uuid.uuid4())

        # Create resource group
        target_region = prep.scenario.region or cfg.settings.default_region
        tags = rg_manager.generate_tags(
            scenario_name=prep.scenario.name,
            deployment_id=deployment_id,
            branch=git_branch,
            owner_email=cfg.settings.owner_email,
            cleanup_mode=cleanup,
            expires_hours=24,
        )

        console.print(f"[cyan]Creating resource group for {prep.scenario.name}...[/cyan]")
        if not rg_manager.create_resource_group(rg_name, target_region, tags):
            console.print(f"[red]✗ Failed to create resource group for {prep.scenario.name}[/red]")
            continue

        # Create deployment state
        state = DeploymentState(
            deployment_id=deployment_id,
            resource_group_name=rg_name,
            deployment_name=deploy_name,
            scenario_name=prep.scenario.name,
            git_branch=git_branch,
            parameter_file_path=str(prep.parameter_file),
            cleanup_mode=cleanup,
            status="pending",
        )

        # Save initial state
        rg_manager.save_deployment_state(state)

        # Create orchestrator for this scenario's template
        orchestrator = DeploymentOrchestrator(
            template_file=prep.engine.template_file,
            resource_group_manager=rg_manager,
        )

        # Submit deployment
        if orchestrator.submit_deployment(state, prep.parameter_file, wait=False):
            deployments.append(ScenarioDeployment(
                state=state,
                engine=prep.engine,
                orchestrator=orchestrator,
            ))
        else:
            console.print(f"[red]✗ Failed to submit deployment for {prep.scenario.name}[/red]")

    if not deployments:
        console.print("\n[red]No deployments were submitted successfully[/red]")
        raise typer.Exit(1)

    console.print(f"\n[green]✓ Submitted {len(deployments)} deployment(s)[/green]")

    # Monitor deployments
    console.print(f"\n[bold]Monitoring Deployments[/bold]\n")
    deployment_states = [d.state for d in deployments]
    final_statuses = monitor.monitor_deployments(
        deployment_states,
        show_live_dashboard=True,
    )

    # Process completed deployments
    console.print(f"\n[bold]Processing Deployment Outputs[/bold]\n")

    succeeded_count = 0
    failed_count = 0

    for d in deployments:
        final_status = final_statuses.get(d.state.deployment_id)

        if final_status == "Succeeded":
            succeeded_count += 1

            # Query instance type and storage details (VMSS for Enterprise, VM for CE)
            vmss_info = d.orchestrator.get_instance_info(d.state.resource_group_name)
            if vmss_info:
                controller = vmss_info["disk_controller_type"]
                controller_color = "green" if controller == "NVME" else "yellow"
                console.print(f"  [cyan]{d.state.scenario_name}[/cyan] instance details:")
                console.print(f"    VM Size:          [bold]{vmss_info['vm_size']}[/bold]")
                console.print(f"    Disk Controller:  [{controller_color}]{controller}[/{controller_color}]")
                if vmss_info.get("disk_size_gb"):
                    console.print(f"    Disk Size:        {vmss_info['disk_size_gb']} GB")
                if vmss_info.get("storage_account_type"):
                    console.print(f"    Storage Type:     {vmss_info['storage_account_type']}")
                console.print()

            # Extract outputs
            outputs = d.orchestrator.extract_outputs(
                d.state.resource_group_name,
                d.state.deployment_name,
            )

            if outputs:
                # Find scenario for this deployment
                scenario_match = next(
                    (p.scenario for p in prepared if p.scenario.name == d.state.scenario_name),
                    None,
                )
                if scenario_match:
                    # Get password for this scenario
                    password = d.engine.password_manager.get_password(d.state.scenario_name)

                    # Parse connection info with credentials
                    conn_info = d.orchestrator.parse_connection_info(
                        outputs,
                        d.state,
                        scenario_match,
                        password,
                    )

                    if conn_info:
                        # Save connection info (includes credentials)
                        d.orchestrator.save_connection_info(
                            conn_info,
                            d.state.scenario_name,
                        )
                        console.print(f"[green]✓ Connection info saved for {d.state.scenario_name}[/green]\n")

                        # Auto-cleanup after successful deployment (if configured)
                        cleanup_manager.auto_cleanup_deployment(d.state, no_wait=True)
        else:
            failed_count += 1

            # Auto-cleanup for failed deployments (will respect cleanup mode)
            cleanup_manager.auto_cleanup_deployment(d.state, no_wait=True)

    # Summary
    console.print("\n" + "=" * 60)
    console.print(f"\n[bold]Deployment Summary[/bold]")
    console.print(f"[green]✓ Succeeded:[/green] {succeeded_count}")
    console.print(f"[red]✗ Failed:[/red] {failed_count}")
    console.print(f"[cyan]Total:[/cyan] {len(deployments)}")

    if succeeded_count > 0:
        console.print("\n[cyan]Next steps:[/cyan]")

        # Show validation command for each successful deployment
        for d in deployments:
            if final_statuses.get(d.state.deployment_id) == "Succeeded":
                console.print(f"  - Validate {d.state.scenario_name}: [bold]uv run validate_deploy {d.state.scenario_name}[/bold]")

        console.print("  - Check status: [bold]uv run neo4j-deploy status[/bold]")
        console.print("  - Run tests: [bold]uv run neo4j-deploy test[/bold]")

        if cleanup == CleanupMode.MANUAL:
            console.print("\n[cyan]Clean up resources:[/cyan]")
            if deployments:
                example_id = deployments[0].state.deployment_id[:8]
                console.print(f"  - Individual: [bold]uv run neo4j-deploy cleanup --deployment {example_id} --force[/bold]")
            console.print(f"  - All: [bold]uv run neo4j-deploy cleanup --all --force[/bold]")
        else:
            console.print(f"  - Cleanup mode: {cleanup.value} (auto-cleanup {'enabled' if cleanup != CleanupMode.MANUAL else 'disabled'})")

    if failed_count > 0:
        raise typer.Exit(1)
