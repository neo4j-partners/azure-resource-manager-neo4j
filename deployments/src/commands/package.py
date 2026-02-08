"""Package commands - build marketplace archives."""

from pathlib import Path
from typing import Optional

import typer
from typing_extensions import Annotated

from ._shared import console


def _build_package(edition_value: str, env_file: Optional[Path]) -> None:
    """Shared logic for building a marketplace package."""
    from ..models import Edition
    from ..package import PackageBuilder

    ed = Edition(edition_value)

    # Determine paths (run from deployments/ directory)
    deployments_dir = Path(__file__).parent.parent.parent.resolve()
    root_dir = deployments_dir.parent

    template_dir = root_dir / "marketplace" / ed.template_dirname

    if not template_dir.exists():
        console.print(f"[red]Error: Template directory not found: {template_dir}[/red]")
        raise typer.Exit(1)

    # Resolve .env file path
    if env_file:
        env_path = Path(env_file).resolve()
    else:
        env_path = root_dir / ".env"

    # Build the package
    builder = PackageBuilder(
        template_dir=template_dir,
        env_file=env_path,
        output_dir=root_dir,
    )

    success = builder.build(template_name=ed.template_dirname)

    if not success:
        raise typer.Exit(1)


def ee_package(
    env_file: Annotated[
        Optional[Path],
        typer.Option("--env", "-e", help="Path to .env file (default: ../.env from deployments/)")
    ] = None,
) -> None:
    """
    Build Enterprise marketplace package with PID from .env file.

    This command:
    1. Reads NEO4J_PARTNER_PID from .env file
    2. Updates main.bicep with the PID
    3. Compiles Bicep to mainTemplate.json
    4. Creates marketplace zip archive in root directory

    The .env file should contain:
        NEO4J_PARTNER_PID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX

    Examples:
        uv run neo4j-deploy ee-package
        uv run neo4j-deploy ee-package --env /path/to/.env
    """
    _build_package("enterprise", env_file)


def ce_package(
    env_file: Annotated[
        Optional[Path],
        typer.Option("--env", "-e", help="Path to .env file (default: ../.env from deployments/)")
    ] = None,
) -> None:
    """
    Build Community Edition marketplace package with PID from .env file.

    This command:
    1. Reads NEO4J_PARTNER_PID from .env file
    2. Updates main.bicep with the PID
    3. Compiles Bicep to mainTemplate.json
    4. Creates marketplace zip archive in root directory

    The .env file should contain:
        NEO4J_PARTNER_PID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX

    Examples:
        uv run neo4j-deploy ce-package
        uv run neo4j-deploy ce-package --env /path/to/.env
    """
    _build_package("community", env_file)
