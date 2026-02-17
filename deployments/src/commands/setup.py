"""Setup command - interactive setup wizard."""

import typer
from typing_extensions import Annotated

from ..config import ConfigManager
from ..setup import SetupWizard
from ._shared import console


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
