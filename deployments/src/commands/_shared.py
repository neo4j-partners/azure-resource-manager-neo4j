"""Shared utilities for CLI commands."""

from dataclasses import dataclass

import typer
from rich.console import Console

from ..config import ConfigManager
from ..models import ScenarioCollection, Settings
from ..setup import SetupWizard

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


@dataclass
class LoadedConfig:
    """Bundle of initialized configuration objects."""

    config_manager: ConfigManager
    settings: Settings
    scenarios: ScenarioCollection


def load_config() -> LoadedConfig:
    """
    Check initialization and load settings + scenarios.

    Returns:
        LoadedConfig with config_manager, settings, and scenarios

    Raises:
        typer.Exit: If not initialized or config fails to load
    """
    config_manager = check_initialized()

    settings = config_manager.load_settings()
    scenarios = config_manager.load_scenarios()

    if not settings or not scenarios:
        console.print("[red]Error: Configuration not loaded. Run setup first.[/red]")
        raise typer.Exit(1)

    return LoadedConfig(
        config_manager=config_manager,
        settings=settings,
        scenarios=scenarios,
    )
