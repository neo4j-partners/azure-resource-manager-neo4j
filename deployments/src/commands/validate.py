"""Validate command - validate ARM templates without deploying."""

from typing import Optional

import typer
from typing_extensions import Annotated

from ._shared import console, load_config


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
    from ..deployment import DeploymentEngine, get_template_dir
    from ..resource_groups import ResourceGroupManager
    from ..validation import CostEstimator, TemplateValidator

    cfg = load_config()

    # Filter scenarios
    if scenario:
        selected = [s for s in cfg.scenarios.scenarios if s.name == scenario]
        if not selected:
            console.print(f"[red]Error: Scenario '{scenario}' not found[/red]")
            raise typer.Exit(1)
        scenarios_to_validate = selected
    else:
        scenarios_to_validate = cfg.scenarios.scenarios

    # Initialize shared components
    validator = TemplateValidator()
    cost_estimator = CostEstimator()
    rg_manager = ResourceGroupManager()

    # Ensure validation resource group exists
    validation_rg = "arm-validation-temp"
    if not rg_manager.resource_group_exists(validation_rg):
        console.print(f"\n[cyan]Creating validation resource group: {validation_rg}[/cyan]")
        success = rg_manager.create_resource_group(
            validation_rg,
            cfg.settings.default_region,
            tags={"purpose": "arm-template-validation", "managed-by": "neo4j-deploy"},
        )
        if not success:
            console.print(
                "[red]Error: Could not create validation resource group[/red]"
            )
            raise typer.Exit(1)

    console.print(f"\n[bold]Validating {len(scenarios_to_validate)} Scenario(s)[/bold]\n")

    all_valid = True

    # Cache engines by (deployment_type, license_type) to avoid recreating
    engines: dict[tuple, DeploymentEngine] = {}

    for s in scenarios_to_validate:
        console.print(f"\n[bold cyan]Scenario: {s.name}[/bold cyan]")
        console.print("=" * 60)

        # Get or create deployment engine for this scenario's edition
        engine_key = (s.deployment_type, s.license_type)

        if engine_key not in engines:
            base_template_dir = get_template_dir(s.license_type)

            try:
                engines[engine_key] = DeploymentEngine(cfg.settings, base_template_dir)
            except FileNotFoundError as e:
                console.print(f"[red]✗ Template not found: {e}[/red]")
                all_valid = False
                continue

        engine = engines[engine_key]

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
            cfg.settings.max_cost_per_deployment,
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
