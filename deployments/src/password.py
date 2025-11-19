"""
Password management for Neo4j deployments.

Supports multiple password provisioning strategies:
- Generate: Random secure passwords
- Environment: Read from NEO4J_ADMIN_PASSWORD
- Azure Key Vault: Retrieve from Azure Key Vault (or generate and store if not exists)
- Prompt: Interactive user input
"""

import os
import secrets
import string
import subprocess
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.prompt import Prompt

from .models import PasswordStrategy, Settings

console = Console()


class PasswordManager:
    """Manages password provisioning based on configured strategy."""

    def __init__(self, settings: Settings) -> None:
        """
        Initialize the password manager.

        Args:
            settings: Application settings containing password strategy
        """
        self.settings = settings
        self.strategy = settings.password_strategy
        self._cached_password: Optional[str] = None
        self._vault_name: Optional[str] = None
        self._vault_resource_group: Optional[str] = None
        self._secret_name: str = "neo4j-admin-password"

    def get_password(self, scenario_name: str) -> str:
        """
        Get admin password based on configured strategy.

        Args:
            scenario_name: Name of the scenario being deployed (for context)

        Returns:
            Admin password string

        Raises:
            ValueError: If password cannot be obtained
        """
        if self._cached_password:
            return self._cached_password

        if self.strategy == PasswordStrategy.GENERATE:
            password = self._generate_password()
        elif self.strategy == PasswordStrategy.ENVIRONMENT:
            password = self._get_from_environment()
        elif self.strategy == PasswordStrategy.AZURE_KEYVAULT:
            password = self._get_from_keyvault()
        elif self.strategy == PasswordStrategy.PROMPT:
            password = self._prompt_for_password(scenario_name)
        else:
            raise ValueError(f"Unknown password strategy: {self.strategy}")

        # Cache for subsequent deployments in same session
        self._cached_password = password
        return password

    def clear_cache(self) -> None:
        """Clear cached password (useful between scenarios)."""
        self._cached_password = None

    def _generate_password(self) -> str:
        """
        Generate a random secure password.

        Returns:
            Generated password (24 characters, alphanumeric + special chars)
        """
        # Azure requires passwords to have 3 of: lowercase, uppercase, numbers, special chars
        # We'll ensure we have all 4 for maximum security

        alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+[]{}|;:,.<>?"

        while True:
            password = "".join(secrets.choice(alphabet) for _ in range(24))

            # Verify password meets Azure requirements
            has_lower = any(c.islower() for c in password)
            has_upper = any(c.isupper() for c in password)
            has_digit = any(c.isdigit() for c in password)
            has_special = any(c in "!@#$%^&*()-_=+[]{}|;:,.<>?" for c in password)

            if has_lower and has_upper and has_digit and has_special:
                console.print("[dim]Generated secure password[/dim]")
                return password

    def _get_from_environment(self) -> str:
        """
        Get password from NEO4J_ADMIN_PASSWORD environment variable.

        Returns:
            Password from environment

        Raises:
            ValueError: If environment variable not set or empty
        """
        password = os.environ.get("NEO4J_ADMIN_PASSWORD")

        if not password:
            raise ValueError(
                "Password strategy is 'environment' but NEO4J_ADMIN_PASSWORD "
                "environment variable is not set. Set it with:\n"
                "  export NEO4J_ADMIN_PASSWORD='your-password'"
            )

        if len(password) < 12:
            console.print(
                "[yellow]Warning: Password from environment is shorter than "
                "recommended (12+ characters)[/yellow]"
            )

        console.print("[dim]Using password from environment variable[/dim]")
        return password

    def _get_from_keyvault(self) -> str:
        """
        Get password from Azure Key Vault.

        If the secret doesn't exist, generates and stores a new password.

        Returns:
            Password from Key Vault

        Raises:
            ValueError: If Key Vault not configured or secret not found
        """
        from .utils import run_command

        if not self.settings.azure_keyvault_name:
            raise ValueError(
                "Password strategy is 'azure-keyvault' but Key Vault name "
                "not configured. Re-run setup or set azure_keyvault_name in settings."
            )

        vault_name = self.settings.azure_keyvault_name
        self._vault_name = vault_name
        # Vault resource group follows naming convention: {prefix}-keyvault
        self._vault_resource_group = f"{self.settings.resource_group_prefix}-keyvault"
        secret_name = self._secret_name

        try:
            console.print(
                f"[dim]Retrieving password from Key Vault: {vault_name}[/dim]"
            )

            result = run_command(
                f"az keyvault secret show --vault-name {vault_name} "
                f"--name {secret_name} --query value -o tsv"
            )

            password = result.stdout.strip()

            if not password:
                raise ValueError(f"Secret '{secret_name}' exists but is empty")

            console.print(f"[green]✓[/green] Retrieved password from Key Vault")
            return password

        except Exception as e:
            # Secret doesn't exist - try to generate and store
            console.print(
                f"[yellow]Password not found in vault, generating new password...[/yellow]"
            )
            try:
                password = self.generate_and_store_in_keyvault(vault_name, secret_name)
                console.print(f"[green]✓[/green] Generated and stored password in Key Vault")
                return password
            except Exception as gen_error:
                raise ValueError(
                    f"Failed to retrieve or generate password from Key Vault '{vault_name}': {e}\n"
                    f"Generation error: {gen_error}\n"
                    f"Ensure:\n"
                    f"  1. Key Vault '{vault_name}' exists\n"
                    f"  2. You have 'set' permission on the Key Vault\n"
                    f"  3. You have access to the Key Vault\n"
                    f"Run: az keyvault secret set --vault-name {vault_name} "
                    f"--name {secret_name} --value 'your-password'"
                ) from e

    def _prompt_for_password(self, scenario_name: str) -> str:
        """
        Prompt user for password interactively.

        Args:
            scenario_name: Scenario name for context in prompt

        Returns:
            User-provided password

        Raises:
            ValueError: If password is empty or too short
        """
        console.print(
            f"\n[cyan]Password required for scenario: {scenario_name}[/cyan]"
        )
        console.print(
            "[dim]Password must be 12-72 characters and contain 3 of: "
            "uppercase, lowercase, numbers, special characters[/dim]"
        )

        password = Prompt.ask(
            "Enter Neo4j admin password",
            password=True,  # Hides input
        )

        if not password:
            raise ValueError("Password cannot be empty")

        if len(password) < 12:
            raise ValueError(
                f"Password too short ({len(password)} chars). "
                f"Azure requires 12-72 characters."
            )

        if len(password) > 72:
            raise ValueError(
                f"Password too long ({len(password)} chars). "
                f"Azure allows maximum 72 characters."
            )

        # Verify complexity requirements
        has_lower = any(c.islower() for c in password)
        has_upper = any(c.isupper() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_special = any(not c.isalnum() for c in password)

        complexity_count = sum([has_lower, has_upper, has_digit, has_special])

        if complexity_count < 3:
            raise ValueError(
                "Password must contain at least 3 of: "
                "uppercase, lowercase, numbers, special characters"
            )

        return password

    def generate_and_store_in_keyvault(
        self,
        vault_name: str,
        secret_name: str = "neo4j-admin-password",
    ) -> str:
        """
        Generate a password using generate-password.sh and store it in Key Vault.

        Args:
            vault_name: Name of the Azure Key Vault
            secret_name: Name of the secret to create

        Returns:
            The generated password

        Raises:
            RuntimeError: If password generation or storage fails
        """
        from .utils import run_command

        # Find the generate-password.sh script
        # It should be in scripts/ relative to the repository root
        script_path = Path(__file__).parent.parent.parent / "scripts" / "generate-password.sh"

        if not script_path.exists():
            raise RuntimeError(
                f"Password generation script not found at: {script_path}\n"
                f"Expected location: scripts/generate-password.sh"
            )

        try:
            # Run the password generation script
            console.print(f"[dim]Generating secure password...[/dim]")
            result = subprocess.run(
                [str(script_path)],
                capture_output=True,
                text=True,
                check=True,
            )

            password = result.stdout.strip()

            if not password or len(password) < 16:
                raise RuntimeError(
                    f"Generated password is invalid (length: {len(password)})"
                )

            # Store the password in Key Vault
            console.print(
                f"[dim]Storing password in Key Vault: {vault_name}/{secret_name}[/dim]"
            )

            # Use subprocess directly to avoid shell quoting issues
            result = subprocess.run(
                [
                    "az", "keyvault", "secret", "set",
                    "--vault-name", vault_name,
                    "--name", secret_name,
                    "--value", password,
                    "--output", "none"
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            # Cache vault name for later retrieval
            self._vault_name = vault_name

            return password

        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to generate password: {e.stderr}"
            ) from e
        except Exception as e:
            raise RuntimeError(
                f"Failed to store password in Key Vault: {e}"
            ) from e

    def get_vault_parameters(self) -> dict[str, str]:
        """
        Get Key Vault parameters for Bicep deployment.

        Returns:
            Dictionary with keyVaultName, keyVaultResourceGroup, and adminPasswordSecretName parameters.
            Returns empty dict if not using Key Vault strategy.
        """
        if self.strategy == PasswordStrategy.AZURE_KEYVAULT and self._vault_name:
            return {
                "keyVaultName": self._vault_name,
                "keyVaultResourceGroup": self._vault_resource_group or "",
                "adminPasswordSecretName": self._secret_name,
            }
        return {}

    def is_using_keyvault(self) -> bool:
        """
        Check if the password manager is configured to use Key Vault.

        Returns:
            True if using Key Vault strategy, False otherwise
        """
        return self.strategy == PasswordStrategy.AZURE_KEYVAULT

    @staticmethod
    def create_keyvault(
        vault_name: str,
        resource_group: str,
        location: str,
    ) -> bool:
        """
        Create an Azure Key Vault for password storage.

        Args:
            vault_name: Name for the new Key Vault (must be globally unique)
            resource_group: Resource group for the vault
            location: Azure region for the vault

        Returns:
            True if vault was created successfully, False otherwise

        Raises:
            RuntimeError: If vault creation fails
        """
        from .utils import run_command

        try:
            console.print(f"[cyan]Creating Key Vault: {vault_name}[/cyan]")

            # Check if vault already exists
            try:
                result = run_command(
                    f"az keyvault show --name {vault_name} --query id -o tsv"
                )
                if result.stdout.strip():
                    console.print(f"[yellow]Key Vault '{vault_name}' already exists, reusing it[/yellow]")
                    # Set access policy for current user
                    PasswordManager._grant_current_user_access(vault_name)
                    return True
            except Exception:
                # Vault doesn't exist, proceed with creation
                pass

            # Create resource group if it doesn't exist
            console.print(f"[dim]Ensuring resource group exists: {resource_group}[/dim]")
            run_command(
                f"az group create --name {resource_group} --location {location} --output none"
            )

            # Create Key Vault with access policies (not RBAC for simplicity)
            console.print(f"[dim]Creating Key Vault in {location}...[/dim]")
            run_command(
                f"az keyvault create "
                f"--name {vault_name} "
                f"--resource-group {resource_group} "
                f"--location {location} "
                f"--enable-rbac-authorization false "
                f"--output none"
            )

            # Grant current user access to manage secrets
            PasswordManager._grant_current_user_access(vault_name)

            console.print(f"[green]✓ Key Vault created successfully: {vault_name}[/green]")
            return True

        except Exception as e:
            raise RuntimeError(
                f"Failed to create Key Vault '{vault_name}': {e}\n"
                f"Ensure:\n"
                f"  1. Vault name is globally unique\n"
                f"  2. You have permissions to create vaults\n"
                f"  3. Azure CLI is authenticated"
            ) from e

    @staticmethod
    def _grant_current_user_access(vault_name: str) -> None:
        """Grant the current user access to Key Vault secrets."""
        from .utils import run_command

        try:
            # Get current user's UPN
            result = run_command(
                "az ad signed-in-user show --query userPrincipalName -o tsv"
            )
            upn = result.stdout.strip()

            console.print(f"[dim]Granting access to current user: {upn}[/dim]")

            # Set access policy for secret operations
            run_command(
                f"az keyvault set-policy "
                f"--name {vault_name} "
                f"--upn {upn} "
                f"--secret-permissions get list set delete "
                f"--output none"
            )

            console.print(f"[green]✓ Access granted to Key Vault[/green]")

        except Exception as e:
            console.print(
                f"[yellow]Warning: Could not grant access automatically: {e}[/yellow]"
            )
            console.print(
                f"[yellow]You may need to manually grant access to vault: {vault_name}[/yellow]"
            )
