"""
Neo4j deployment testing using Python validator.

Handles:
- Executing connectivity tests against deployed instances using Python Neo4j driver
- Parsing test results
- Updating deployment state with test status
- Logging test output
"""

from pathlib import Path
from typing import Optional

from rich.console import Console

from .constants import LOGS_DIR
from .models import ConnectionInfo, TestResult
from .password import PasswordManager
from .resource_groups import ResourceGroupManager
from .utils import ensure_directory, get_timestamp
from .validate_deploy import Neo4jValidator

console = Console()


class Neo4jTester:
    """Manages Neo4j deployment testing using Python validator."""

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
        ensure_directory(LOGS_DIR)

    def test_deployment(
        self,
        conn_info: ConnectionInfo,
        scenario_name: str,
        license_type: str,
        deployment_id: str,
    ) -> TestResult:
        """
        Test a deployed Neo4j instance using Python validator.

        Args:
            conn_info: Connection information for the deployment (includes credentials)
            scenario_name: Scenario name for logging
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

        # Prepare log file
        timestamp = get_timestamp()
        log_file = LOGS_DIR / f"test-{scenario_name}-{timestamp}.log"

        console.print(f"[dim]Connecting to: {conn_info.neo4j_uri}[/dim]")
        console.print(f"[dim]License type: {license_type}[/dim]")
        console.print(f"[dim]Logging to: {log_file}[/dim]")

        # Capture output for logging
        output_lines = []

        try:
            # Use Python validator
            with Neo4jValidator(
                conn_info.neo4j_uri,
                conn_info.username,
                conn_info.password
            ) as validator:
                # Run full validation
                passed = validator.run_full_validation(license_type)

            # Create success output
            if passed:
                output = "All validation tests passed successfully"
                exit_code = 0
            else:
                output = "Validation tests failed"
                exit_code = 1

            # Save log file
            log_content = f"""Neo4j Python Validator Output
{'=' * 80}
URI: {conn_info.neo4j_uri}
Username: {conn_info.username}
License Type: {license_type}
Resource Group: {conn_info.resource_group}
Timestamp: {timestamp}

{'=' * 80}
Result: {'PASSED' if passed else 'FAILED'}
Exit Code: {exit_code}
Output: {output}
"""
            with open(log_file, "w") as f:
                f.write(log_content)

            # Create test result
            test_result = TestResult(
                deployment_id=deployment_id,
                scenario_name=scenario_name,
                passed=passed,
                exit_code=exit_code,
                output=output[:1000],  # Truncate long output
                log_file=str(log_file),
            )

            # Display results
            if passed:
                console.print(
                    f"[green]✓ Test PASSED for {conn_info.resource_group}[/green]"
                )
            else:
                console.print(
                    f"[red]✗ Test FAILED for {conn_info.resource_group}[/red]"
                )
                console.print(f"[yellow]See log file: {log_file}[/yellow]")

            # Update deployment state
            self.rg_manager.update_deployment_test_status(
                deployment_id,
                passed,
                test_result.model_dump(mode="json"),
            )

            return test_result

        except Exception as e:
            error_msg = f"Test execution failed: {e}"
            console.print(f"[red]✗ {error_msg}[/red]")

            # Save error log
            log_content = f"""Neo4j Python Validator Error
{'=' * 80}
URI: {conn_info.neo4j_uri}
Resource Group: {conn_info.resource_group}
Timestamp: {timestamp}

{'=' * 80}
Error: {error_msg}
"""
            with open(log_file, "w") as f:
                f.write(log_content)

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
