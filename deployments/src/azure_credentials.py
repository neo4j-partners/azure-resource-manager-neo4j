"""
Setup Azure Service Principal for GitHub Actions.

This script automates the creation of an Azure Service Principal for
authenticating GitHub Actions workflows with Azure.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Annotated, Optional

import typer
from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.syntax import Syntax

app = typer.Typer(help="Setup Azure credentials for GitHub Actions")
console = Console()


class AzureCredentialsSetup:
    """Handles Azure Service Principal creation and configuration."""

    def __init__(
        self,
        sp_name: str = "github-actions-neo4j-deploy",
        subscription_id: Optional[str] = None,
        output_file: Path = Path("azure-credentials.json"),
    ):
        self.sp_name = sp_name
        self.subscription_id = subscription_id
        self.output_file = output_file
        self.needs_role_assignment = False

    def check_prerequisites(self) -> bool:
        """Check if Azure CLI is installed and user is logged in."""
        console.print("\n[bold blue]Checking Prerequisites[/bold blue]\n")

        # Check Azure CLI
        try:
            result = subprocess.run(
                ["az", "version"],
                capture_output=True,
                text=True,
                check=True,
            )
            version_info = json.loads(result.stdout)
            az_version = version_info.get("azure-cli", "unknown")
            console.print(f"[green]✓[/green] Azure CLI is installed (version: {az_version})")
        except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
            console.print("[red]✗[/red] Azure CLI is not installed")
            console.print("\nInstall from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli")
            return False

        # Check Azure login status
        try:
            result = subprocess.run(
                ["az", "account", "show"],
                capture_output=True,
                text=True,
                check=True,
            )
            account_info = json.loads(result.stdout)
            console.print(f"[green]✓[/green] Logged in to Azure")
            console.print(f"  Account: {account_info['name']}")
            console.print(f"  Subscription ID: {account_info['id']}")

            if not self.subscription_id:
                self.subscription_id = account_info["id"]

        except (subprocess.CalledProcessError, json.JSONDecodeError):
            console.print("[red]✗[/red] Not logged in to Azure CLI")
            console.print("\nPlease login first:")
            console.print("  az login")
            return False

        return True

    def confirm_subscription(self) -> bool:
        """Confirm the Azure subscription to use."""
        console.print("\n[bold blue]Confirming Subscription[/bold blue]\n")

        if not self.subscription_id:
            console.print("[red]✗[/red] No subscription ID available")
            return False

        try:
            result = subprocess.run(
                ["az", "account", "show", "--subscription", str(self.subscription_id)],
                capture_output=True,
                text=True,
                check=True,
            )
            account_info = json.loads(result.stdout)
            sub_name = account_info["name"]

            console.print("Service principal will be created for:")
            console.print(f"  Subscription: {sub_name}")
            console.print(f"  ID: {self.subscription_id}")
            console.print()

            return Confirm.ask("Is this correct?")

        except (subprocess.CalledProcessError, json.JSONDecodeError):
            console.print(f"[red]✗[/red] Invalid subscription ID: {self.subscription_id}")
            return False

    def check_existing_sp(self) -> bool:
        """Check for existing service principal and handle accordingly."""
        console.print("\n[bold blue]Checking for Existing Service Principal[/bold blue]\n")

        try:
            result = subprocess.run(
                [
                    "az",
                    "ad",
                    "sp",
                    "list",
                    "--display-name",
                    self.sp_name,
                    "--query",
                    "[0].appId",
                    "-o",
                    "tsv",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            app_id = result.stdout.strip()

            if app_id:
                console.print(f"[yellow]⚠[/yellow] A service principal named '{self.sp_name}' already exists")
                console.print(f"  Application ID: {app_id}")
                console.print()
                console.print("Options:")
                console.print("  1. Delete existing and create new (will invalidate existing credentials)")
                console.print("  2. Create with a different name")
                console.print("  3. Cancel")

                choice = Prompt.ask("Choose option", choices=["1", "2", "3"], default="3")

                if choice == "1":
                    console.print("[blue]ℹ[/blue] Deleting existing service principal...")
                    subprocess.run(
                        ["az", "ad", "sp", "delete", "--id", app_id],
                        check=True,
                        capture_output=True,
                    )
                    console.print("[green]✓[/green] Existing service principal deleted")
                elif choice == "2":
                    self.sp_name = Prompt.ask("Enter new name")
                    return self.check_existing_sp()  # Recursive check with new name
                else:
                    console.print("[blue]ℹ[/blue] Cancelled by user")
                    return False
            else:
                console.print(f"[green]✓[/green] No existing service principal found with name '{self.sp_name}'")

        except subprocess.CalledProcessError as e:
            console.print(f"[red]✗[/red] Error checking for existing service principal: {e}")
            return False

        return True

    def create_service_principal(self) -> Optional[dict]:
        """Create the service principal with Contributor role."""
        console.print("\n[bold blue]Creating Service Principal[/bold blue]\n")

        console.print("[blue]ℹ[/blue] Creating service principal with Contributor role...")
        console.print(f"  Name: {self.sp_name}")
        console.print(f"  Scope: /subscriptions/{self.subscription_id}")
        console.print(f"  Role: Contributor")
        console.print()

        # Try to create with role assignment first
        try:
            result = subprocess.run(
                [
                    "az",
                    "ad",
                    "sp",
                    "create-for-rbac",
                    "--name",
                    self.sp_name,
                    "--role",
                    "Contributor",
                    "--scopes",
                    f"/subscriptions/{self.subscription_id}",
                    "--sdk-auth",
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            # Parse JSON from output (filter out WARNING lines)
            output_lines = [
                line for line in result.stdout.split("\n") if not line.startswith("WARNING:")
            ]
            credentials_json = json.loads("\n".join(output_lines))

            console.print("[green]✓[/green] Service principal created successfully")
            return credentials_json

        except subprocess.CalledProcessError as e:
            # Check if it's an authorization error
            if "AuthorizationFailed" in e.stderr or "AuthorizationFailed" in e.stdout:
                console.print(
                    "[yellow]⚠[/yellow] Insufficient permissions to assign role automatically"
                )
                console.print()
                console.print("[blue]ℹ[/blue] Creating service principal without role assignment...")
                console.print("  (Role will need to be assigned manually by an administrator)")
                console.print()

                # Create without role assignment
                try:
                    result = subprocess.run(
                        [
                            "az",
                            "ad",
                            "sp",
                            "create-for-rbac",
                            "--name",
                            self.sp_name,
                            "--skip-assignment",
                            "--sdk-auth",
                        ],
                        capture_output=True,
                        text=True,
                        check=True,
                    )

                    # Parse JSON from output (filter out WARNING lines)
                    output_lines = [
                        line
                        for line in result.stdout.split("\n")
                        if not line.startswith("WARNING:")
                    ]
                    credentials_json = json.loads("\n".join(output_lines))

                    console.print("[green]✓[/green] Service principal created successfully")
                    console.print(
                        "[yellow]⚠[/yellow] Role assignment required (see next steps below)"
                    )

                    self.needs_role_assignment = True
                    return credentials_json

                except (subprocess.CalledProcessError, json.JSONDecodeError) as e2:
                    console.print(f"[red]✗[/red] Failed to create service principal: {e2}")
                    return None
            else:
                console.print(f"[red]✗[/red] Failed to create service principal")
                console.print("\nError details:")
                console.print(e.stderr or e.stdout)
                return None

    def save_credentials(self, credentials: dict) -> bool:
        """Save credentials to file."""
        console.print("\n[bold blue]Saving Credentials[/bold blue]\n")

        # Check if file exists
        if self.output_file.exists():
            console.print(f"[yellow]⚠[/yellow] Output file '{self.output_file}' already exists")
            if not Confirm.ask("Overwrite?"):
                console.print("[blue]ℹ[/blue] Not saving to file")
                return False

        # Save to file
        try:
            self.output_file.write_text(json.dumps(credentials, indent=2))
            self.output_file.chmod(0o600)  # Restrict permissions

            console.print(f"[green]✓[/green] Credentials saved to: {self.output_file}")
            console.print("[yellow]⚠[/yellow] File permissions set to 600 (owner read/write only)")

            # Validate JSON
            try:
                saved_data = json.loads(self.output_file.read_text())
                if "clientId" in saved_data:
                    console.print("[green]✓[/green] JSON format validated")
                else:
                    console.print("[red]✗[/red] Invalid JSON format in output file")
                    return False
            except json.JSONDecodeError:
                console.print("[red]✗[/red] Invalid JSON format in output file")
                return False

            return True

        except Exception as e:
            console.print(f"[red]✗[/red] Failed to save credentials: {e}")
            return False

    def add_to_gitignore(self) -> None:
        """Add credentials file to .gitignore."""
        gitignore_file = Path(".gitignore")

        if not gitignore_file.exists():
            console.print(f"[yellow]⚠[/yellow] .gitignore not found in current directory")
            return

        gitignore_content = gitignore_file.read_text()

        if str(self.output_file.name) in gitignore_content:
            console.print(f"[green]✓[/green] {self.output_file.name} already in .gitignore")
        else:
            with gitignore_file.open("a") as f:
                f.write(f"\n{self.output_file.name}\n")
            console.print(f"[green]✓[/green] Added {self.output_file.name} to .gitignore")

    def display_next_steps(self, credentials: dict) -> None:
        """Display next steps for completing the setup."""
        console.print("\n[bold blue]Next Steps[/bold blue]\n")

        step = 1

        # Show role assignment step if needed
        if self.needs_role_assignment:
            app_id = credentials.get("appId", credentials.get("clientId"))

            console.print(f"[bold]{step}. ASSIGN CONTRIBUTOR ROLE (Required by Administrator)[/bold]")
            console.print("   The service principal was created but needs role assignment.")
            console.print("   Ask an Azure administrator to run:")
            console.print()

            command = f"""az role assignment create \\
  --assignee "{app_id}" \\
  --role "Contributor" \\
  --scope "/subscriptions/{self.subscription_id}" """

            syntax = Syntax(command, "bash", theme="monokai", line_numbers=False)
            console.print(syntax)
            console.print()
            console.print("   Or use Azure Portal:")
            console.print("   - Go to: Subscriptions → Access control (IAM)")
            console.print("   - Click: '+ Add' → 'Add role assignment'")
            console.print("   - Role: Contributor")
            console.print(f"   - Members: Search for '{self.sp_name}'")
            console.print()
            step += 1

        # Add credentials to GitHub
        console.print(f"[bold]{step}. Add the credentials to GitHub repository secrets:[/bold]")
        console.print(
            "   - Go to: https://github.com/neo4j-partners/azure-resource-manager-neo4j/settings/secrets/actions"
        )
        console.print("   - Click: 'New repository secret'")
        console.print("   - Name: AZURE_CREDENTIALS")
        console.print(f"   - Value: Copy the entire JSON from {self.output_file}")
        console.print()
        step += 1

        # Verify setup
        console.print(f"[bold]{step}. Verify the setup:[/bold]")
        console.print("   Test authentication locally:")
        console.print()

        client_id = credentials.get("clientId")
        tenant_id = credentials.get("tenantId")

        verify_command = f"""az login --service-principal \\
  --username "{client_id}" \\
  --password "<CLIENT_SECRET from {self.output_file}>" \\
  --tenant "{tenant_id}"

az group list --output table"""

        syntax = Syntax(verify_command, "bash", theme="monokai", line_numbers=False)
        console.print(syntax)
        console.print()
        step += 1

        # Test GitHub Actions
        console.print(f"[bold]{step}. Test GitHub Actions workflow:[/bold]")
        console.print("   - Go to Actions tab in GitHub")
        console.print("   - Select 'Test Bicep Template for Enterprise'")
        console.print("   - Click 'Run workflow'")
        console.print()

        if self.needs_role_assignment:
            console.print(
                "[yellow]⚠ IMPORTANT: Complete step 1 (role assignment) before testing GitHub Actions![/yellow]"
            )
            console.print()

        # Security reminders
        panel = Panel(
            f"""• Never commit {self.output_file} to source control
• Add {self.output_file} to .gitignore if not already present
• Rotate the client secret every 12 months
• Delete {self.output_file} after adding to GitHub (or store securely)""",
            title="[yellow]Security Reminders[/yellow]",
            border_style="yellow",
        )
        console.print(panel)
        console.print()
        console.print("[blue]ℹ[/blue] For detailed documentation, see ENTRA.md")

    def run(self) -> bool:
        """Run the complete setup process."""
        # Print header
        console.print()
        console.print(
            Panel.fit(
                "[bold]Azure Service Principal Setup for GitHub Actions[/bold]",
                border_style="blue",
            )
        )

        # Check prerequisites
        if not self.check_prerequisites():
            return False

        # Confirm subscription
        if not self.confirm_subscription():
            console.print("[blue]ℹ[/blue] Cancelled by user")
            return False

        # Check for existing service principal
        if not self.check_existing_sp():
            return False

        # Create service principal
        credentials = self.create_service_principal()
        if not credentials:
            return False

        # Save credentials
        if not self.save_credentials(credentials):
            return False

        # Add to gitignore
        self.add_to_gitignore()

        # Display next steps
        self.display_next_steps(credentials)

        console.print("[green]✓[/green] Setup complete!")
        return True


@app.command()
def main(
    name: Annotated[
        str,
        typer.Option("--name", "-n", help="Service principal name"),
    ] = "github-actions-neo4j-deploy",
    subscription: Annotated[
        Optional[str],
        typer.Option("--subscription", "-s", help="Azure subscription ID (default: current subscription)"),
    ] = None,
    output: Annotated[
        Path,
        typer.Option("--output", "-o", help="Output file for credentials"),
    ] = Path("azure-credentials.json"),
) -> None:
    """
    Setup Azure Service Principal for GitHub Actions.

    This script automates the creation of an Azure Service Principal for
    authenticating GitHub Actions workflows with Azure.
    """
    setup = AzureCredentialsSetup(
        sp_name=name,
        subscription_id=subscription,
        output_file=output,
    )

    success = setup.run()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    app()
