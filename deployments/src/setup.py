"""
Interactive setup wizard for first-time configuration.
"""

from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, IntPrompt, Prompt
from rich.table import Table

from .config import ConfigManager
from .constants import (
    CLEANUP_MODES,
    DEFAULT_CLEANUP_MODE,
    DEFAULT_REGIONS,
    NEO4J_VERSIONS,
)
from .models import (
    CleanupMode,
    PasswordStrategy,
    ScenarioCollection,
    Settings,
    TestScenario,
)
from .utils import (
    console,
    get_az_account_info,
    get_az_default_location,
    get_git_remote_url,
    get_git_user_email,
    parse_github_url,
)

console = Console()


class SetupWizard:
    """Interactive setup wizard for first-time configuration."""

    def __init__(self) -> None:
        """Initialize the setup wizard."""
        self.config_manager = ConfigManager()

    def run(self) -> bool:
        """
        Run the interactive setup wizard.

        Returns:
            True if setup completed successfully, False otherwise
        """
        # Step 1: Welcome
        if not self._show_welcome():
            console.print("[yellow]Setup cancelled.[/yellow]")
            return False

        # Step 2: Azure subscription detection
        az_info = self._detect_azure_subscription()
        if not az_info:
            console.print(
                "[red]Error: Could not detect Azure subscription. "
                "Please run 'az login' and try again.[/red]"
            )
            return False

        # Step 3: Default region
        default_region = self._select_region()

        # Step 4: Resource naming
        resource_group_prefix = self._configure_resource_naming()

        # Step 5: Cleanup behavior
        cleanup_mode = self._select_cleanup_mode()

        # Step 6: Test scenarios
        create_scenarios = Confirm.ask(
            "Create default test scenarios?", default=True
        )

        # Step 7: Password configuration
        password_strategy, vault_name = self._configure_password_strategy(
            default_region, resource_group_prefix
        )

        # Step 8: Finalize
        owner_email = get_git_user_email() or Prompt.ask(
            "Enter your email for resource tagging"
        )

        # Auto-detect Git info without prompting
        git_url = get_git_remote_url()
        github_info = parse_github_url(git_url) if git_url else None
        auto_detect_branch = True if github_info else False

        # Create Settings object
        settings = Settings(
            subscription_id=az_info["id"],
            subscription_name=az_info["name"],
            default_region=default_region,
            resource_group_prefix=resource_group_prefix,
            default_cleanup_mode=CleanupMode(cleanup_mode),
            max_cost_per_deployment=None,  # Disabled
            auto_detect_branch=auto_detect_branch,
            repository_org=github_info[0] if github_info else None,
            repository_name=github_info[1] if github_info else None,
            password_strategy=password_strategy,
            azure_keyvault_name=vault_name,
            owner_email=owner_email,
        )

        # Show summary
        self._show_summary(settings)

        # Auto-save configuration
        console.print("\n[cyan]Saving configuration...[/cyan]")
        self.config_manager.initialize_directories()
        self.config_manager.save_settings(settings)

        # Create scenarios if requested
        if create_scenarios:
            scenarios = self._create_default_scenarios()
            self.config_manager.save_scenarios(scenarios)

        # Create example templates
        self.config_manager.create_example_templates()

        # Update README
        self._update_readme()

        console.print("\n[bold green]✓ Setup complete![/bold green]")
        console.print("You can now run:")
        console.print("  [cyan]uv run neo4j-deploy validate[/cyan]     - Validate templates")
        console.print("  [cyan]uv run neo4j-deploy deploy --all[/cyan] - Deploy all scenarios")
        console.print("  [cyan]uv run neo4j-deploy status[/cyan]       - Check deployment status")

        return True

    def _show_welcome(self) -> bool:
        """Show welcome message and get confirmation to continue."""
        welcome_text = """
[bold]Welcome to the Neo4j Azure Deployment Tools Setup[/bold]

This wizard will help you configure the testing environment:
• Azure subscription and region settings
• Resource naming conventions
• Cleanup behavior
• Test scenario configuration
• Password management strategy

All configuration will be stored in [cyan].arm-testing/config/[/cyan]
Working files (logs, results, state) will be in [cyan].arm-testing/[/cyan]
The [cyan].arm-testing/[/cyan] directory is already git-ignored.

You can run this setup again anytime with: [cyan]uv run neo4j-deploy setup[/cyan]
        """

        console.print(Panel(welcome_text, title="Setup Wizard", border_style="blue"))
        return Confirm.ask("Continue with setup?", default=True)

    def _detect_azure_subscription(self) -> Optional[dict]:
        """Detect current Azure subscription."""
        console.print("\n[bold]Step 2: Azure Subscription Detection[/bold]")

        az_info = get_az_account_info()
        if not az_info:
            return None

        table = Table(title="Current Azure Subscription")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="white")

        table.add_row("Subscription ID", az_info["id"])
        table.add_row("Subscription Name", az_info["name"])
        table.add_row("Tenant ID", az_info["tenantId"])
        table.add_row("User", az_info["user"]["name"])

        console.print(table)

        if not Confirm.ask("Use this subscription for testing?", default=True):
            console.print(
                "[yellow]Please run 'az account set --subscription <name>' "
                "and try again.[/yellow]"
            )
            return None

        return az_info

    def _select_region(self) -> str:
        """Select default Azure region."""
        console.print("\n[bold]Step 3: Default Azure Region[/bold]")

        # Try to detect default region from Azure CLI
        detected_region = get_az_default_location()

        if detected_region:
            console.print(f"[cyan]Detected Azure default location: {detected_region}[/cyan]")
            if Confirm.ask(f"Use {detected_region} as default region?", default=True):
                return detected_region

        console.print("Select default region for test deployments:")

        for i, region in enumerate(DEFAULT_REGIONS, 1):
            console.print(f"  {i}. {region}")
        console.print(f"  {len(DEFAULT_REGIONS) + 1}. Custom (enter manually)")

        # Default to first region in list
        default_choice = 1

        # If detected region is in the list, use it as default
        if detected_region and detected_region in DEFAULT_REGIONS:
            default_choice = DEFAULT_REGIONS.index(detected_region) + 1

        choice = IntPrompt.ask(
            "Enter choice",
            default=default_choice,
            choices=[str(i) for i in range(1, len(DEFAULT_REGIONS) + 2)],
        )

        if choice == len(DEFAULT_REGIONS) + 1:
            default_region_value = detected_region or "westeurope"
            return Prompt.ask("Enter Azure region", default=default_region_value)
        else:
            return DEFAULT_REGIONS[choice - 1]

    def _configure_resource_naming(self) -> str:
        """Configure resource naming convention."""
        console.print("\n[bold]Step 4: Resource Naming Convention[/bold]")
        console.print(
            "Resource groups will be named: [cyan]{prefix}-{scenario}-{timestamp}[/cyan]"
        )
        console.print("Example: [cyan]neo4j-test-standalone-v5-20250116-143052[/cyan]")

        use_default = Confirm.ask(
            "Use default prefix 'neo4j-test'?", default=True
        )

        if use_default:
            return "neo4j-test"
        else:
            return Prompt.ask("Enter resource group prefix", default="neo4j-test")

    def _select_cleanup_mode(self) -> str:
        """Select default cleanup mode."""
        console.print("\n[bold]Step 5: Default Cleanup Behavior[/bold]")
        console.print("Available cleanup modes:")
        console.print("  1. [cyan]immediate[/cyan]  - Delete resources right after test")
        console.print("  2. [cyan]on-success[/cyan] - Delete only if tests pass")
        console.print("  3. [cyan]manual[/cyan]     - Never auto-delete (recommended)")
        console.print(
            "  4. [cyan]scheduled[/cyan]  - Tag resources to expire after N hours"
        )

        choice = IntPrompt.ask("Enter choice", default=3, choices=["1", "2", "3", "4"])

        mode_map = {
            1: "immediate",
            2: "on-success",
            3: "manual",
            4: "scheduled",
        }

        return mode_map[choice]

    def _configure_password_strategy(
        self, default_region: str, resource_group_prefix: str
    ) -> tuple[PasswordStrategy, Optional[str]]:
        """
        Configure password provisioning strategy.

        Args:
            default_region: Default Azure region
            resource_group_prefix: Prefix for resource group names

        Returns:
            Tuple of (password strategy, vault name if applicable)
        """
        console.print("\n[bold]Step 6: Neo4j Password Configuration[/bold]")
        console.print("How should admin passwords be provided?")
        console.print("  1. [cyan]Generate[/cyan] random secure password per deployment (recommended)")
        console.print("  2. [cyan]Environment[/cyan] variable NEO4J_ADMIN_PASSWORD")
        console.print("  3. [cyan]Prompt[/cyan] each time")

        choice = IntPrompt.ask("Enter choice", default=1, choices=["1", "2", "3"])

        strategy_map = {
            1: PasswordStrategy.GENERATE,
            2: PasswordStrategy.ENVIRONMENT,
            3: PasswordStrategy.PROMPT,
        }

        strategy = strategy_map[choice]

        return strategy, None


    def _create_default_scenarios(self) -> ScenarioCollection:
        """Create default test scenarios."""
        from .models import DeploymentType

        scenarios = [
            TestScenario(
                name="standalone-v5",
                deployment_type=DeploymentType.VM,
                node_count=1,
                graph_database_version="5",
                vm_size="Standard_E4s_v5",
                disk_size=32,
                license_type="Evaluation",
            ),
            TestScenario(
                name="cluster-v5",
                deployment_type=DeploymentType.VM,
                node_count=3,
                graph_database_version="5",
                vm_size="Standard_E4s_v5",
                disk_size=32,
                license_type="Evaluation",
            ),
            TestScenario(
                name="standalone-v44",
                deployment_type=DeploymentType.VM,
                node_count=1,
                graph_database_version="4.4",
                vm_size="Standard_E4s_v5",
                disk_size=32,
                license_type="Evaluation",
            ),
            TestScenario(
                name="community-standalone-v5",
                deployment_type=DeploymentType.COMMUNITY,
                node_count=1,
                graph_database_version="5",
                vm_size="Standard_B2s",
                disk_size=32,
                license_type="Evaluation",
            ),
            TestScenario(
                name="standard-aks-v5",
                deployment_type=DeploymentType.AKS,
                node_count=1,
                graph_database_version="5",
                disk_size=32,
                license_type="Evaluation",
                kubernetes_version="1.31",
                user_node_size="Standard_E4s_v5",
                user_node_count_min=1,
                user_node_count_max=10,
                install_graph_data_science=False,
                install_bloom=False,
            ),
            TestScenario(
                name="cluster-3node-aks-v5",
                deployment_type=DeploymentType.AKS,
                node_count=3,
                graph_database_version="5",
                disk_size=32,
                license_type="Evaluation",
                kubernetes_version="1.31",
                user_node_size="Standard_E4s_v5",
                user_node_count_min=3,
                user_node_count_max=10,
                install_graph_data_science=False,
                install_bloom=False,
            ),
            TestScenario(
                name="cluster-5node-aks-v5",
                deployment_type=DeploymentType.AKS,
                node_count=5,
                graph_database_version="5",
                disk_size=32,
                license_type="Evaluation",
                kubernetes_version="1.31",
                user_node_size="Standard_E4s_v5",
                user_node_count_min=5,
                user_node_count_max=10,
                install_graph_data_science=False,
                install_bloom=False,
            ),
        ]

        return ScenarioCollection(scenarios=scenarios)

    def _show_summary(self, settings: Settings) -> None:
        """Show configuration summary."""
        console.print("\n[bold]Configuration Summary[/bold]")

        table = Table()
        table.add_column("Setting", style="cyan")
        table.add_column("Value", style="white")

        table.add_row("Subscription", settings.subscription_name)
        table.add_row("Default Region", settings.default_region)
        table.add_row("Resource Prefix", settings.resource_group_prefix)
        table.add_row("Cleanup Mode", settings.default_cleanup_mode.value)
        table.add_row("Password Strategy", settings.password_strategy.value)
        table.add_row("Owner Email", settings.owner_email)
        if settings.repository_org and settings.repository_name:
            table.add_row("Repository", f"{settings.repository_org}/{settings.repository_name}")

        console.print(table)

    def _update_readme(self) -> None:
        """Create or update README.md in deployments directory."""
        readme_content = """# Neo4j Azure Deployment Tools

Automated deployment and testing framework for Neo4j Enterprise on Azure.

## Quick Start

```bash
# First-time setup (already completed)
uv run neo4j-deploy setup

# Validate templates
uv run neo4j-deploy validate

# Deploy all scenarios
uv run neo4j-deploy deploy --all

# Deploy specific scenario
uv run neo4j-deploy deploy --scenario standalone-v5

# Check deployment status
uv run neo4j-deploy status

# Generate test report
uv run neo4j-deploy report

# Clean up resources
uv run neo4j-deploy cleanup --all
```

## Configuration

Configuration files are located in `.arm-testing/config/`:
- `settings.yaml` - Main settings (Azure subscription, regions, cleanup modes)
- `scenarios.yaml` - Test scenario definitions

Example templates are in `.arm-testing/templates/`

## Directory Structure

```
.arm-testing/
├── config/       # Configuration files
├── state/        # Deployment tracking
├── params/       # Generated parameter files
├── results/      # Test outputs and reports
├── logs/         # Execution logs
├── cache/        # Downloaded binaries
└── templates/    # Example configurations
```

## Requirements

- Python 3.12+ with uv
- Azure CLI (`az`) installed and configured
- Git (for automatic branch detection)
- Active Azure subscription

## Documentation

See SCRIPT_PROPOSAL.md in marketplace/neo4j-enterprise/ for detailed implementation specifications.
"""

        readme_path = Path("README.md")
        with open(readme_path, "w") as f:
            f.write(readme_content)

        console.print(f"[green]Updated {readme_path}[/green]")