"""
Neo4j deployment testing using neo4jtester.

Handles:
- Downloading and caching neo4jtester binary
- Executing connectivity tests against deployed instances
- Parsing test results
- Updating deployment state with test status
- Logging test output
"""

import os
import platform
import stat
import subprocess
from pathlib import Path
from typing import Optional

import requests
from rich.console import Console

from .constants import CACHE_DIR, LOGS_DIR
from .models import ConnectionInfo, TestResult
from .password import PasswordManager
from .resource_groups import ResourceGroupManager
from .utils import ensure_directory, get_timestamp

console = Console()


class Neo4jTester:
    """Manages Neo4j deployment testing using neo4jtester."""

    # Neo4jtester download URLs by platform
    NEO4JTESTER_URLS = {
        "darwin": "https://github.com/neo4j/neo4jtester/raw/main/build/neo4jtester_darwin",
        "linux": "https://github.com/neo4j/neo4jtester/raw/main/build/neo4jtester_linux",
        "windows": "https://github.com/neo4j/neo4jtester/raw/main/build/neo4jtester.exe",
    }

    def __init__(
        self,
        password_manager: PasswordManager,
        resource_group_manager: ResourceGroupManager,
    ) -> None:
        """
        Initialize the Neo4j tester.

        Args:
            password_manager: Password manager for retrieving credentials
            resource_group_manager: Resource group manager for updating state
        """
        self.password_manager = password_manager
        self.rg_manager = resource_group_manager

        # Ensure required directories exist
        ensure_directory(CACHE_DIR)
        ensure_directory(LOGS_DIR)

        # Get platform-specific neo4jtester path
        self.neo4jtester_binary = self._get_neo4jtester_path()

    def _get_neo4jtester_path(self) -> Path:
        """
        Get platform-specific neo4jtester binary path.

        Returns:
            Path to neo4jtester binary in cache directory
        """
        system = platform.system().lower()

        if system == "darwin":
            binary_name = "neo4jtester_darwin"
        elif system == "linux":
            binary_name = "neo4jtester_linux"
        elif system == "windows":
            binary_name = "neo4jtester.exe"
        else:
            raise RuntimeError(f"Unsupported platform: {system}")

        return CACHE_DIR / binary_name

    def _download_neo4jtester(self) -> None:
        """
        Download neo4jtester binary if not cached.

        Raises:
            RuntimeError: If download fails
        """
        if self.neo4jtester_binary.exists():
            console.print(
                f"[dim]Using cached neo4jtester: {self.neo4jtester_binary}[/dim]"
            )
            return

        system = platform.system().lower()
        url = self.NEO4JTESTER_URLS.get(system)

        if not url:
            raise RuntimeError(f"No neo4jtester binary available for platform: {system}")

        console.print(f"[cyan]Downloading neo4jtester from {url}...[/cyan]")

        try:
            response = requests.get(url, timeout=60, stream=True)
            response.raise_for_status()

            # Download with progress (simplified)
            with open(self.neo4jtester_binary, "wb") as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)

            # Make executable (Unix-like systems)
            if system in ["darwin", "linux"]:
                self.neo4jtester_binary.chmod(
                    self.neo4jtester_binary.stat().st_mode | stat.S_IEXEC
                )

            console.print(
                f"[green]✓ Downloaded neo4jtester to {self.neo4jtester_binary}[/green]"
            )

        except requests.RequestException as e:
            raise RuntimeError(f"Failed to download neo4jtester: {e}") from e
        except OSError as e:
            raise RuntimeError(f"Failed to save neo4jtester binary: {e}") from e

    def test_deployment(
        self,
        conn_info: ConnectionInfo,
        scenario_name: str,
        license_type: str,
        deployment_id: str,
    ) -> TestResult:
        """
        Test a deployed Neo4j instance using neo4jtester.

        Args:
            conn_info: Connection information for the deployment
            scenario_name: Scenario name for password lookup
            license_type: License type ("Enterprise" or "Evaluation")
            deployment_id: Deployment ID for state tracking

        Returns:
            TestResult object with test status and details

        Raises:
            RuntimeError: If test execution fails
        """
        console.print(
            f"[cyan]Testing deployment: {conn_info.resource_group}[/cyan]"
        )

        # Ensure neo4jtester is available
        self._download_neo4jtester()

        # Get password
        password = self.password_manager.get_password(scenario_name)

        # Determine edition for neo4jtester
        # License type "Evaluation" maps to "enterprise" edition
        # License type "Enterprise" also maps to "enterprise" edition
        edition = "enterprise" if license_type in ["Enterprise", "Evaluation"] else "community"

        # Build neo4jtester command
        # neo4jtester expects: <URI> <username> <password> <edition>
        command = [
            str(self.neo4jtester_binary),
            conn_info.neo4j_uri,
            "neo4j",  # Default Neo4j username
            password,
            edition,
        ]

        # Prepare log file
        timestamp = get_timestamp()
        log_file = LOGS_DIR / f"test-{scenario_name}-{timestamp}.log"

        console.print(f"[dim]Executing: {' '.join(command[:3])} *** {edition}[/dim]")
        console.print(f"[dim]Logging to: {log_file}[/dim]")

        try:
            # Execute neo4jtester
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=120,  # 2 minute timeout for tests
                check=False,
            )

            # Save full output to log file
            log_content = f"""Neo4j Tester Output
{'=' * 80}
Command: {' '.join(command[:3])} *** {edition}
URI: {conn_info.neo4j_uri}
Resource Group: {conn_info.resource_group}
Timestamp: {timestamp}

{'=' * 80}
STDOUT:
{result.stdout}

{'=' * 80}
STDERR:
{result.stderr}

{'=' * 80}
Exit Code: {result.returncode}
"""
            with open(log_file, "w") as f:
                f.write(log_content)

            # Parse results
            passed = result.returncode == 0
            output = result.stdout if result.stdout else result.stderr

            # Create test result
            test_result = TestResult(
                deployment_id=deployment_id,
                scenario_name=scenario_name,
                passed=passed,
                exit_code=result.returncode,
                output=output[:1000],  # Truncate long output
                log_file=str(log_file),
            )

            # Display results
            if passed:
                console.print(
                    f"[green]✓ Test PASSED for {conn_info.resource_group}[/green]"
                )
                console.print(f"[dim]Output: {output[:200]}...[/dim]")
            else:
                console.print(
                    f"[red]✗ Test FAILED for {conn_info.resource_group}[/red]"
                )
                console.print(f"[red]Exit code: {result.returncode}[/red]")
                console.print(f"[red]Output: {output[:500]}[/red]")
                console.print(f"[yellow]See log file: {log_file}[/yellow]")

            # Update deployment state
            self.rg_manager.update_deployment_test_status(
                deployment_id,
                passed,
                test_result.model_dump(mode="json"),
            )

            return test_result

        except subprocess.TimeoutExpired:
            error_msg = "Test timed out after 120 seconds"
            console.print(f"[red]✗ {error_msg}[/red]")

            test_result = TestResult(
                deployment_id=deployment_id,
                scenario_name=scenario_name,
                passed=False,
                exit_code=-1,
                output=error_msg,
                log_file=str(log_file),
            )

            self.rg_manager.update_deployment_test_status(
                deployment_id,
                False,
                test_result.model_dump(mode="json"),
            )

            return test_result

        except Exception as e:
            error_msg = f"Test execution failed: {e}"
            console.print(f"[red]✗ {error_msg}[/red]")

            test_result = TestResult(
                deployment_id=deployment_id,
                scenario_name=scenario_name,
                passed=False,
                exit_code=-1,
                output=error_msg,
                log_file=str(log_file) if log_file else None,
            )

            self.rg_manager.update_deployment_test_status(
                deployment_id,
                False,
                test_result.model_dump(mode="json"),
            )

            return test_result

    def load_connection_info(self, results_dir: Path, scenario_name: str) -> Optional[ConnectionInfo]:
        """
        Load the most recent connection info file for a scenario.

        Args:
            results_dir: Directory containing connection info files
            scenario_name: Scenario name to search for

        Returns:
            ConnectionInfo object or None if not found
        """
        # Find all connection files for this scenario
        pattern = f"connection-{scenario_name}-*.json"
        files = sorted(results_dir.glob(pattern), reverse=True)

        if not files:
            console.print(
                f"[yellow]No connection info files found for scenario: {scenario_name}[/yellow]"
            )
            return None

        # Load most recent file
        from .utils import load_json

        latest_file = files[0]
        console.print(f"[dim]Loading connection info from: {latest_file}[/dim]")

        try:
            data = load_json(latest_file)
            return ConnectionInfo(**data)
        except Exception as e:
            console.print(
                f"[yellow]Failed to load connection info from {latest_file}: {e}[/yellow]"
            )
            return None
