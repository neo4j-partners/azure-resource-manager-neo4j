"""CLI commands for neo4j-deploy."""

from typer import Typer


def register_commands(app: Typer) -> None:
    """Register all CLI commands on the Typer app."""
    from .cleanup import cleanup
    from .deploy import deploy
    from .package import ce_package, ee_package
    from .report import report
    from .setup import setup
    from .status import status
    from .test import test
    from .validate import validate

    app.command()(setup)
    app.command()(validate)
    app.command()(deploy)
    app.command()(test)
    app.command()(status)
    app.command()(cleanup)
    app.command()(report)
    app.command("ee-package")(ee_package)
    app.command("ce-package")(ce_package)
