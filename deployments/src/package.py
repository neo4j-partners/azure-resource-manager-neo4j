"""
Marketplace package builder for Neo4j Azure templates.

Handles:
- Reading PID from .env file
- Updating Bicep template with PID
- Compiling Bicep to ARM JSON
- Creating marketplace zip archive
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from rich.console import Console

console = Console()


class PackageBuilder:
    """Builds marketplace packages for Neo4j Azure templates."""

    # Pattern to match the PID in Bicep files
    # Matches either:
    #   name: 'pid-UUID-partnercenter'  (full format)
    #   name: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'  (placeholder)
    PID_PATTERN = re.compile(
        r"(name:\s*')(?:pid-)?([a-fA-F0-9X-]+)(?:-partnercenter)?(')"
    )

    def __init__(
        self,
        template_dir: Path,
        env_file: Path,
        output_dir: Path,
    ):
        """
        Initialize the package builder.

        Args:
            template_dir: Path to the marketplace template directory (e.g., marketplace/neo4j-enterprise)
            env_file: Path to the .env file containing the PID
            output_dir: Path to output the zip file
        """
        self.template_dir = template_dir
        self.env_file = env_file
        self.output_dir = output_dir

        # Template files
        self.bicep_file = template_dir / "main.bicep"
        self.ui_definition_file = template_dir / "createUiDefinition.json"

    def load_pid_from_env(self) -> Optional[str]:
        """
        Load the NEO4J_PARTNER_PID from the .env file.

        Returns:
            The PID (UUID format), or None if not found
        """
        if not self.env_file.exists():
            console.print(f"[red]Error: .env file not found at {self.env_file}[/red]")
            return None

        load_dotenv(self.env_file)
        pid = os.getenv("NEO4J_PARTNER_PID")

        if not pid:
            console.print("[red]Error: NEO4J_PARTNER_PID not found in .env file[/red]")
            return None

        # Validate UUID format
        uuid_pattern = re.compile(
            r"^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$"
        )
        if not uuid_pattern.match(pid):
            console.print(f"[red]Error: Invalid PID format: {pid}[/red]")
            console.print("[yellow]Expected UUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX[/yellow]")
            return None

        return pid

    def update_bicep_with_pid(self, pid: str, bicep_content: str) -> str:
        """
        Update the Bicep content with the new PID.

        Args:
            pid: The partner PID (UUID format)
            bicep_content: The original Bicep file content

        Returns:
            Updated Bicep content with full PID format: pid-UUID-partnercenter
        """
        def replace_pid(match):
            # Output full format: name: 'pid-UUID-partnercenter'
            return f"{match.group(1)}pid-{pid}-partnercenter{match.group(3)}"

        updated_content, count = self.PID_PATTERN.subn(replace_pid, bicep_content)

        if count == 0:
            console.print("[yellow]Warning: No PID placeholder found in Bicep file[/yellow]")
        else:
            console.print(f"[green]✓ Updated {count} PID reference(s) in Bicep[/green]")

        return updated_content

    def compile_bicep(self, bicep_file: Path, output_file: Path) -> bool:
        """
        Compile Bicep to ARM JSON using az bicep build.

        Args:
            bicep_file: Path to the Bicep file
            output_file: Path for the output JSON file

        Returns:
            True if compilation succeeded, False otherwise
        """
        try:
            result = subprocess.run(
                [
                    "az", "bicep", "build",
                    "--file", str(bicep_file),
                    "--outfile", str(output_file),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            console.print(f"[green]✓ Compiled Bicep to {output_file.name}[/green]")
            return True
        except subprocess.CalledProcessError as e:
            console.print(f"[red]Error compiling Bicep:[/red]")
            console.print(f"[red]{e.stderr}[/red]")
            return False
        except FileNotFoundError:
            console.print("[red]Error: 'az' CLI not found. Please install Azure CLI.[/red]")
            return False

    def create_zip_archive(
        self,
        json_file: Path,
        ui_definition_file: Path,
        output_zip: Path,
    ) -> bool:
        """
        Create the marketplace zip archive.

        Args:
            json_file: Path to mainTemplate.json
            ui_definition_file: Path to createUiDefinition.json
            output_zip: Path for the output zip file

        Returns:
            True if zip creation succeeded, False otherwise
        """
        try:
            # Use zip command for compatibility with Azure marketplace
            result = subprocess.run(
                [
                    "zip", "-j",  # -j: junk paths (don't include directory structure)
                    str(output_zip),
                    str(ui_definition_file),
                    str(json_file),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            console.print(f"[green]✓ Created archive: {output_zip}[/green]")
            return True
        except subprocess.CalledProcessError as e:
            console.print(f"[red]Error creating zip archive:[/red]")
            console.print(f"[red]{e.stderr}[/red]")
            return False
        except FileNotFoundError:
            console.print("[red]Error: 'zip' command not found.[/red]")
            return False

    def build(self, template_name: str = "neo4j-enterprise") -> bool:
        """
        Build the complete marketplace package.

        Args:
            template_name: Name for the output zip file (without extension)

        Returns:
            True if build succeeded, False otherwise
        """
        console.print(f"\n[bold]Building Marketplace Package[/bold]\n")
        console.print(f"[dim]Template directory: {self.template_dir}[/dim]")
        console.print(f"[dim]Environment file: {self.env_file}[/dim]")
        console.print(f"[dim]Output directory: {self.output_dir}[/dim]\n")

        # Step 1: Load PID from .env
        console.print("[cyan]Step 1: Loading PID from .env...[/cyan]")
        pid = self.load_pid_from_env()
        if not pid:
            return False
        console.print(f"[dim]PID: {pid[:8]}...{pid[-4:]}[/dim]\n")

        # Step 2: Read and update Bicep file
        console.print("[cyan]Step 2: Updating Bicep with PID...[/cyan]")
        if not self.bicep_file.exists():
            console.print(f"[red]Error: Bicep file not found: {self.bicep_file}[/red]")
            return False

        bicep_content = self.bicep_file.read_text()
        updated_bicep = self.update_bicep_with_pid(pid, bicep_content)

        # Step 3: Write updated Bicep to temp file and compile
        console.print("\n[cyan]Step 3: Compiling Bicep to ARM JSON...[/cyan]")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_bicep = Path(temp_dir) / "main.bicep"
            temp_json = Path(temp_dir) / "main.json"

            # Copy all module files to temp directory
            modules_dir = self.template_dir / "modules"
            if modules_dir.exists():
                temp_modules = Path(temp_dir) / "modules"
                shutil.copytree(modules_dir, temp_modules)

            # Copy scripts directory if referenced (for loadTextContent)
            scripts_dir = self.template_dir.parent.parent / "scripts"
            if scripts_dir.exists():
                temp_scripts = Path(temp_dir).parent.parent / "scripts"
                if not temp_scripts.exists():
                    # Create symlink to scripts directory
                    temp_scripts_parent = Path(temp_dir).parent.parent
                    temp_scripts_parent.mkdir(parents=True, exist_ok=True)
                    # Copy scripts to expected relative path
                    target_scripts = Path(temp_dir) / ".." / ".." / "scripts"
                    target_scripts = target_scripts.resolve()
                    if not target_scripts.exists():
                        target_scripts.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copytree(scripts_dir, target_scripts)

            # Write updated Bicep
            temp_bicep.write_text(updated_bicep)

            # Compile - use original directory for proper relative path resolution
            # Instead, update the original file temporarily
            original_content = self.bicep_file.read_text()
            self.bicep_file.write_text(updated_bicep)

            output_json = self.template_dir / "mainTemplate.json"

            try:
                if not self.compile_bicep(self.bicep_file, output_json):
                    # Restore original content
                    self.bicep_file.write_text(original_content)
                    return False
            finally:
                # Restore original Bicep content
                self.bicep_file.write_text(original_content)

        # Step 4: Verify UI definition exists
        console.print("\n[cyan]Step 4: Verifying createUiDefinition.json...[/cyan]")
        if not self.ui_definition_file.exists():
            console.print(f"[red]Error: UI definition not found: {self.ui_definition_file}[/red]")
            return False
        console.print(f"[green]✓ Found createUiDefinition.json[/green]")

        # Step 5: Create zip archive
        console.print("\n[cyan]Step 5: Creating marketplace archive...[/cyan]")
        output_zip = self.output_dir / f"{template_name}.zip"

        if not self.create_zip_archive(output_json, self.ui_definition_file, output_zip):
            return False

        # Summary
        console.print("\n" + "=" * 60)
        console.print(f"\n[bold green]✓ Package built successfully![/bold green]\n")
        console.print(f"[cyan]Output files:[/cyan]")
        console.print(f"  - {output_json}")
        console.print(f"  - {output_zip}")
        console.print(f"\n[dim]Upload {output_zip.name} to Azure Partner Portal[/dim]")

        return True
