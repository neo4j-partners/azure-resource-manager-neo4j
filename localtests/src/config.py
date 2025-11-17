"""
Configuration management for the ARM template testing suite.
"""

from pathlib import Path
from typing import Optional

from pydantic import ValidationError
from rich.console import Console

from .constants import (
    ARM_TESTING_DIR,
    CONFIG_DIR,
    LOGS_DIR,
    PARAMS_DIR,
    RESULTS_DIR,
    SCENARIOS_FILE,
    SETTINGS_FILE,
    STATE_DIR,
    TEMPLATES_DIR,
)
from .models import ScenarioCollection, Settings
from .utils import load_yaml, save_yaml

console = Console()


class ConfigManager:
    """Manages configuration loading, saving, and validation."""

    def __init__(self) -> None:
        """Initialize the configuration manager."""
        self.settings: Optional[Settings] = None
        self.scenarios: Optional[ScenarioCollection] = None

    def is_initialized(self) -> bool:
        """
        Check if the testing suite has been initialized.

        Returns:
            True if .arm-testing directory and config files exist
        """
        return ARM_TESTING_DIR.exists() and SETTINGS_FILE.exists()

    def initialize_directories(self) -> None:
        """Create all necessary directories for the testing suite."""
        directories = [
            ARM_TESTING_DIR,
            CONFIG_DIR,
            STATE_DIR,
            PARAMS_DIR,
            RESULTS_DIR,
            LOGS_DIR,
            TEMPLATES_DIR,
        ]

        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)

        console.print(
            f"[green]Created directory structure in {ARM_TESTING_DIR}[/green]"
        )

    def load_settings(self) -> Optional[Settings]:
        """
        Load settings from YAML file.

        Returns:
            Settings object or None if file doesn't exist
        """
        if not SETTINGS_FILE.exists():
            return None

        try:
            data = load_yaml(SETTINGS_FILE)
            self.settings = Settings(**data)
            return self.settings
        except ValidationError as e:
            console.print(f"[red]Invalid settings file: {e}[/red]")
            raise
        except Exception as e:
            console.print(f"[red]Error loading settings: {e}[/red]")
            raise

    def save_settings(self, settings: Settings) -> None:
        """
        Save settings to YAML file.

        Args:
            settings: Settings object to save
        """
        try:
            # Use mode='json' to serialize enums as their values
            data = settings.model_dump(mode='json', exclude_none=True)
            save_yaml(data, SETTINGS_FILE)
            self.settings = settings
            console.print(f"[green]Settings saved to {SETTINGS_FILE}[/green]")
        except Exception as e:
            console.print(f"[red]Error saving settings: {e}[/red]")
            raise

    def load_scenarios(self) -> Optional[ScenarioCollection]:
        """
        Load test scenarios from YAML file.

        Returns:
            ScenarioCollection object or None if file doesn't exist
        """
        if not SCENARIOS_FILE.exists():
            return None

        try:
            data = load_yaml(SCENARIOS_FILE)
            self.scenarios = ScenarioCollection(**data)
            return self.scenarios
        except ValidationError as e:
            console.print(f"[red]Invalid scenarios file: {e}[/red]")
            raise
        except Exception as e:
            console.print(f"[red]Error loading scenarios: {e}[/red]")
            raise

    def save_scenarios(self, scenarios: ScenarioCollection) -> None:
        """
        Save test scenarios to YAML file.

        Args:
            scenarios: ScenarioCollection object to save
        """
        try:
            # Use mode='json' to serialize enums as their values
            data = scenarios.model_dump(mode='json', exclude_none=True)
            save_yaml(data, SCENARIOS_FILE)
            self.scenarios = scenarios
            console.print(f"[green]Scenarios saved to {SCENARIOS_FILE}[/green]")
        except Exception as e:
            console.print(f"[red]Error saving scenarios: {e}[/red]")
            raise

    def create_example_templates(self) -> None:
        """Create example configuration templates."""
        # Example settings
        example_settings = {
            "subscription_id": "your-subscription-id-here",
            "subscription_name": "Your Subscription Name",
            "default_region": "westeurope",
            "resource_group_prefix": "neo4j-test",
            "default_cleanup_mode": "on-success",
            "max_cost_per_deployment": 50.0,
            "auto_detect_branch": True,
            "repository_org": "neo4j-partners",
            "repository_name": "azure-resource-manager-neo4j",
            "password_strategy": "generate",
            "deployment_timeout": 1800,
            "owner_email": "your-email@example.com",
        }

        example_settings_path = TEMPLATES_DIR / "settings.example.yaml"
        save_yaml(example_settings, example_settings_path)
        console.print(f"[green]Created example settings at {example_settings_path}[/green]")

        # Example scenarios
        example_scenarios = {
            "scenarios": [
                {
                    "name": "standalone-v5",
                    "node_count": 1,
                    "graph_database_version": "5",
                    "vm_size": "Standard_E4s_v5",
                    "disk_size": 32,
                    "license_type": "Evaluation",
                    "install_graph_data_science": False,
                    "install_bloom": False,
                },
                {
                    "name": "cluster-v5",
                    "node_count": 3,
                    "graph_database_version": "5",
                    "vm_size": "Standard_E4s_v5",
                    "disk_size": 32,
                    "license_type": "Evaluation",
                    "install_graph_data_science": False,
                    "install_bloom": False,
                },
                {
                    "name": "standalone-v44",
                    "node_count": 1,
                    "graph_database_version": "4.4",
                    "vm_size": "Standard_E4s_v5",
                    "disk_size": 32,
                    "license_type": "Evaluation",
                    "install_graph_data_science": False,
                    "install_bloom": False,
                },
            ]
        }

        example_scenarios_path = TEMPLATES_DIR / "scenarios.example.yaml"
        save_yaml(example_scenarios, example_scenarios_path)
        console.print(f"[green]Created example scenarios at {example_scenarios_path}[/green]")
