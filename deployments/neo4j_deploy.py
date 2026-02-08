#!/usr/bin/env python3
"""
Neo4j Azure Deployment Tools

Main entry point for the deployment and testing framework.
"""

import sys
from pathlib import Path

import typer
from rich.console import Console

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from src.commands import register_commands

# Create Typer app
app = typer.Typer(
    name="neo4j-deploy",
    help="Neo4j Azure Deployment Tools - Automated deployment and testing framework for Neo4j on Azure (Enterprise and Community Edition)",
    add_completion=False,
    rich_markup_mode="rich",
)

register_commands(app)

console = Console()


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
