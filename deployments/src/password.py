"""
Password management for Neo4j deployments.

Supports multiple password provisioning strategies:
- Generate: Random secure passwords
- Environment: Read from NEO4J_ADMIN_PASSWORD
- Azure Key Vault: Retrieve from Azure Key Vault
- Prompt: Interactive user input
"""

import os
import secrets
import string
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
        secret_name = "neo4j-admin-password"

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

            return password

        except Exception as e:
            raise ValueError(
                f"Failed to retrieve password from Key Vault '{vault_name}': {e}\n"
                f"Ensure:\n"
                f"  1. Key Vault '{vault_name}' exists\n"
                f"  2. Secret '{secret_name}' exists\n"
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
