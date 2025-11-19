"""
Deployment orchestration for ARM templates.

Handles:
- Submitting deployments to Azure with --no-wait
- Tracking deployment submission
- Extracting deployment outputs
- Parsing and saving connection information
"""

import json
import re
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

from rich.console import Console

from .constants import RESULTS_DIR
from .models import ConnectionInfo, DeploymentState, TestScenario
from .resource_groups import ResourceGroupManager
from .utils import ensure_directory, get_timestamp, run_command, save_json

console = Console()


class DeploymentOrchestrator:
    """Orchestrates ARM template deployments to Azure."""

    def __init__(
        self,
        template_file: Path,
        resource_group_manager: ResourceGroupManager,
    ) -> None:
        """
        Initialize the deployment orchestrator.

        Args:
            template_file: Path to Bicep template (main.bicep)
            resource_group_manager: Resource group manager instance
        """
        self.template_file = template_file
        self.rg_manager = resource_group_manager

        if not template_file.exists():
            raise FileNotFoundError(f"Template file not found: {template_file}")

    def validate_deployment(
        self,
        resource_group: str,
        parameter_file: Path,
    ) -> tuple[bool, Optional[str]]:
        """
        Validate ARM template before deployment.

        Args:
            resource_group: Resource group name
            parameter_file: Path to parameter file

        Returns:
            Tuple of (is_valid, error_message)
        """
        template_path = self.template_file.resolve()
        params_path = parameter_file.resolve()

        # Run validation with --debug to get actual error messages
        # when Azure CLI bug hides them
        command = (
            f"az deployment group validate "
            f"--resource-group {resource_group} "
            f"--template-file {template_path} "
            f"--parameters {params_path} "
            f"--debug"
        )

        try:
            result = run_command(command, check=False)

            # Check for validation success
            if result.returncode == 0:
                return True, None

            # Parse actual error from debug output
            stderr_content = result.stderr if result.stderr else ""
            stdout_content = result.stdout if result.stdout else ""
            combined_output = stderr_content + "\n" + stdout_content

            # Extract the actual error message from debug output
            error_msg = self._extract_validation_error(combined_output)

            return False, error_msg

        except Exception as e:
            return False, f"Validation failed with exception: {e}"

    def _extract_validation_error(self, debug_output: str) -> str:
        """
        Extract actual error message from Azure CLI debug output.

        Args:
            debug_output: Combined stderr/stdout from validation command

        Returns:
            Extracted error message
        """
        # Look for common error patterns in debug output
        error_patterns = [
            # Authorization errors
            (r"Authorization failed.*?does not have permission to perform action '([^']+)'",
             "Authorization Error: Missing permission for action '{}'"),

            # Invalid template errors
            (r"InvalidTemplateDeployment.*?Message: ([^\n]+)",
             "Template Error: {}"),

            # Response status errors
            (r"Response status: (\d+)",
             "Azure returned status code: {}"),
        ]

        import re

        # Try to extract specific error details
        for pattern, message_template in error_patterns:
            match = re.search(pattern, debug_output, re.IGNORECASE | re.DOTALL)
            if match:
                if len(match.groups()) > 0:
                    return message_template.format(match.group(1))

        # Check for authorization errors specifically
        if "Authorization failed" in debug_output:
            # Extract the authorization error details
            auth_match = re.search(
                r"does not have permission to perform action '([^']+)'.*?at scope",
                debug_output,
                re.DOTALL
            )
            if auth_match:
                action = auth_match.group(1)
                return (
                    f"Authorization Error: Your Azure account lacks permission to perform '{action}'.\n"
                    f"This template requires Owner or User Access Administrator role on the subscription.\n"
                    f"Contact your Azure administrator to grant the necessary permissions."
                )

        # If no specific pattern matched, return generic error
        if "InvalidTemplateDeployment" in debug_output:
            return "Template validation failed. Run with --debug to see full error details."

        return "Deployment validation failed with unknown error."

    def submit_deployment(
        self,
        deployment_state: DeploymentState,
        parameter_file: Path,
        wait: bool = False,
        skip_validation: bool = False,
    ) -> bool:
        """
        Submit an ARM template deployment to Azure.

        Args:
            deployment_state: Deployment state tracking object
            parameter_file: Path to parameter file
            wait: If True, wait for deployment to complete (default: False)
            skip_validation: If True, skip pre-deployment validation (default: False)

        Returns:
            True if deployment submitted successfully, False otherwise
        """
        console.print(
            f"[cyan]Submitting deployment: {deployment_state.deployment_name}[/cyan]"
        )

        # Validate template before deployment (unless skipped)
        if not skip_validation:
            console.print("[dim]Validating template...[/dim]")
            is_valid, error_msg = self.validate_deployment(
                deployment_state.resource_group_name,
                parameter_file
            )

            if not is_valid:
                console.print(
                    f"[red]✗ Template validation failed: {deployment_state.deployment_name}[/red]"
                )
                console.print(f"[red]{error_msg}[/red]")

                # Update state to failed
                self.rg_manager.update_deployment_status(
                    deployment_state.deployment_id, "failed"
                )
                return False

            console.print("[green]✓ Template validation passed[/green]")

        # Build Azure CLI command
        wait_flag = "" if wait else "--no-wait"

        # Ensure paths are absolute
        template_path = self.template_file.resolve()
        params_path = parameter_file.resolve()

        # Note: Don't use @ symbol with local files - it causes Azure CLI errors
        # The @ symbol is only for inline JSON or URIs
        # Use --only-show-errors to suppress Azure CLI logging bugs
        command = (
            f"az deployment group create "
            f"--resource-group {deployment_state.resource_group_name} "
            f"--name {deployment_state.deployment_name} "
            f"--template-file {template_path} "
            f"--parameters {params_path} "
            f"{wait_flag} "
            f"--only-show-errors "
            f"--output json"
        )

        try:
            # Debug: print the command
            console.print(f"[dim]Executing: {command}[/dim]")

            result = run_command(command, check=False)

            # Store stdout and stderr immediately
            stdout_content = result.stdout if result.stdout else ""
            stderr_content = result.stderr if result.stderr else ""

            # Azure CLI bug: Sometimes shows "content already consumed" error even on success
            # However, if validation passed and we see this error, we need to verify
            # the deployment was actually created
            is_spurious_error = "The content for this response was already consumed" in stderr_content

            if result.returncode == 0:
                # Clean success
                self.rg_manager.update_deployment_status(
                    deployment_state.deployment_id, "deploying"
                )

                if wait:
                    console.print(
                        f"[green]✓ Deployment completed: {deployment_state.deployment_name}[/green]"
                    )
                else:
                    console.print(
                        f"[green]✓ Deployment submitted: {deployment_state.deployment_name}[/green]"
                    )
                return True

            elif is_spurious_error:
                # Azure CLI bug - but validation passed, so check if deployment exists
                console.print(
                    f"[yellow]⚠ Azure CLI returned spurious error (known bug)[/yellow]"
                )
                console.print(
                    f"[dim]Verifying deployment was created...[/dim]"
                )

                # Wait a moment for Azure to register the deployment
                import time
                time.sleep(3)

                # Check if deployment exists
                verify_cmd = (
                    f"az deployment group show "
                    f"--resource-group {deployment_state.resource_group_name} "
                    f"--name {deployment_state.deployment_name} "
                    f"--query name --output tsv"
                )
                verify_result = run_command(verify_cmd, check=False)

                if verify_result.returncode == 0 and verify_result.stdout.strip():
                    # Deployment was created successfully despite the error
                    console.print(
                        f"[green]✓ Deployment verified: {deployment_state.deployment_name}[/green]"
                    )
                    self.rg_manager.update_deployment_status(
                        deployment_state.deployment_id, "deploying"
                    )
                    return True
                else:
                    # Deployment was not created - real failure
                    console.print(
                        f"[red]✗ Deployment was not created despite passing validation[/red]"
                    )
                    console.print(
                        f"[red]This may be a transient Azure issue. Try again.[/red]"
                    )
                    self.rg_manager.update_deployment_status(
                        deployment_state.deployment_id, "failed"
                    )
                    return False
            else:
                # Real error
                error_msg = self._parse_deployment_error(stderr_content)
                console.print(
                    f"[red]✗ Failed to submit deployment: {deployment_state.deployment_name}[/red]"
                )
                console.print(f"[red]{error_msg}[/red]")

                # Debug: print full stderr
                if stderr_content:
                    console.print(f"[dim]Full stderr: {stderr_content}[/dim]")

                # Update state to failed
                self.rg_manager.update_deployment_status(
                    deployment_state.deployment_id, "failed"
                )
                return False

        except Exception as e:
            console.print(
                f"[red]✗ Error submitting deployment: {e}[/red]"
            )
            self.rg_manager.update_deployment_status(
                deployment_state.deployment_id, "failed"
            )
            return False

    def extract_outputs(
        self,
        resource_group: str,
        deployment_name: str,
    ) -> Optional[dict]:
        """
        Extract outputs from a completed Azure deployment.

        Args:
            resource_group: Resource group name
            deployment_name: Deployment name

        Returns:
            Dictionary of deployment outputs, or None if extraction failed
        """
        console.print(
            f"[cyan]Extracting outputs for: {deployment_name}[/cyan]"
        )

        try:
            # Query deployment outputs
            command = (
                f"az deployment group show "
                f"--resource-group {resource_group} "
                f"--name {deployment_name} "
                f"--query properties.outputs "
                f"--output json"
            )

            result = run_command(command, check=False)

            if result.returncode == 0 and result.stdout:
                outputs = json.loads(result.stdout)
                console.print(
                    f"[green]✓ Extracted {len(outputs)} output(s)[/green]"
                )
                return outputs
            else:
                console.print(
                    f"[yellow]Warning: Could not extract outputs: {result.stderr}[/yellow]"
                )
                return None

        except json.JSONDecodeError as e:
            console.print(
                f"[yellow]Warning: Invalid JSON in deployment outputs: {e}[/yellow]"
            )
            return None
        except Exception as e:
            console.print(
                f"[yellow]Warning: Error extracting outputs: {e}[/yellow]"
            )
            return None

    def parse_connection_info(
        self,
        outputs: dict,
        deployment_state: DeploymentState,
        scenario: TestScenario,
        password: str,
        username: str = "neo4j",
    ) -> Optional[ConnectionInfo]:
        """
        Parse deployment outputs to extract connection information.

        Args:
            outputs: Raw deployment outputs from Azure
            deployment_state: Deployment state
            scenario: Test scenario
            password: Neo4j admin password
            username: Neo4j username (default: "neo4j")

        Returns:
            ConnectionInfo object or None if parsing failed
        """
        try:
            # Determine which browser URL key to use based on node count
            if scenario.node_count == 1:
                browser_url_key = "neo4jBrowserURL"
            else:
                browser_url_key = "neo4jClusterBrowserURL"

            # Extract browser URL
            browser_url_value = outputs.get(browser_url_key, {}).get("value")
            if not browser_url_value:
                console.print(
                    f"[yellow]Warning: {browser_url_key} not found in outputs[/yellow]"
                )
                return None

            # Convert HTTP browser URL to Neo4j protocol URI
            neo4j_uri = self._convert_to_neo4j_uri(browser_url_value)

            # Extract Bloom URL if present
            bloom_url = None
            if scenario.install_bloom:
                bloom_url_value = outputs.get("neo4jBloomURL", {}).get("value")
                if bloom_url_value:
                    bloom_url = bloom_url_value

            # Create connection info object with credentials
            conn_info = ConnectionInfo(
                deployment_id=deployment_state.deployment_id,
                scenario_name=deployment_state.scenario_name,
                resource_group=deployment_state.resource_group_name,
                neo4j_uri=neo4j_uri,
                browser_url=browser_url_value,
                bloom_url=bloom_url,
                username=username,
                password=password,
                license_type=scenario.license_type,
                node_count=scenario.node_count,
                outputs=outputs,
            )

            console.print(
                f"[green]✓ Parsed connection info: {neo4j_uri}[/green]"
            )
            return conn_info

        except Exception as e:
            console.print(
                f"[yellow]Warning: Error parsing connection info: {e}[/yellow]"
            )
            return None

    def save_connection_info(
        self,
        conn_info: ConnectionInfo,
        scenario_name: str,
    ) -> Optional[Path]:
        """
        Save connection information to results directory.

        Args:
            conn_info: Connection information object
            scenario_name: Scenario name for filename

        Returns:
            Path to saved file, or None if save failed
        """
        try:
            ensure_directory(RESULTS_DIR)

            # Generate filename with timestamp
            timestamp = get_timestamp()
            filename = f"connection-{scenario_name}-{timestamp}.json"
            file_path = RESULTS_DIR / filename

            # Save as JSON
            data = conn_info.model_dump(mode="json")
            save_json(data, file_path)

            console.print(
                f"[green]✓ Connection info saved to: {file_path}[/green]"
            )
            return file_path

        except Exception as e:
            console.print(
                f"[yellow]Warning: Could not save connection info: {e}[/yellow]"
            )
            return None

    def _convert_to_neo4j_uri(self, browser_url: str) -> str:
        """
        Convert HTTP browser URL to Neo4j protocol URI.

        Args:
            browser_url: HTTP browser URL (e.g., http://hostname:7474)

        Returns:
            Neo4j protocol URI (e.g., neo4j://hostname:7687)

        Examples:
            >>> _convert_to_neo4j_uri("http://10.0.1.4:7474")
            "neo4j://10.0.1.4:7687"
        """
        # Parse the URL
        parsed = urlparse(browser_url)

        # Extract hostname (remove port if present)
        hostname = parsed.hostname or parsed.netloc.split(":")[0]

        # Construct Neo4j URI with bolt port
        neo4j_uri = f"neo4j://{hostname}:7687"

        return neo4j_uri

    def _parse_deployment_error(self, stderr: str) -> str:
        """
        Parse Azure CLI error message to extract useful information.

        Args:
            stderr: Standard error output from az command

        Returns:
            Cleaned error message
        """
        if not stderr:
            return "Unknown error"

        # Common error patterns
        if "QuotaExceeded" in stderr:
            return (
                "Deployment failed: Azure quota exceeded\n"
                "Try reducing VM count or size, or request quota increase"
            )
        elif "InvalidTemplateDeployment" in stderr:
            return (
                "Deployment failed: Invalid template or parameters\n"
                "Check parameter values and template syntax"
            )
        elif "AuthorizationFailed" in stderr:
            return (
                "Deployment failed: Authorization error\n"
                "Check Azure subscription permissions"
            )
        elif "ResourceNotFound" in stderr:
            return (
                "Deployment failed: Resource not found\n"
                "Check resource group exists and is in correct region"
            )
        else:
            # Return first line of error for brevity
            lines = stderr.strip().split("\n")
            return lines[0] if lines else stderr


class DeploymentPlanner:
    """Plans and generates deployment metadata."""

    def __init__(self, resource_group_prefix: str) -> None:
        """
        Initialize deployment planner.

        Args:
            resource_group_prefix: Prefix for resource group names
        """
        self.resource_group_prefix = resource_group_prefix

    def generate_resource_group_name(
        self,
        scenario_name: str,
        timestamp: Optional[str] = None,
    ) -> str:
        """
        Generate resource group name.

        Args:
            scenario_name: Scenario name
            timestamp: Optional timestamp (generates new if not provided)

        Returns:
            Resource group name following pattern: {prefix}-{scenario}-{timestamp}

        Example:
            >>> generate_resource_group_name("standalone-v5")
            "neo4j-test-standalone-v5-20250116-143052"
        """
        if not timestamp:
            timestamp = get_timestamp()

        # Azure resource group names: 1-90 chars, alphanumeric + hyphens/underscores
        # Remove any characters that aren't alphanumeric or hyphens
        safe_scenario = re.sub(r"[^a-zA-Z0-9-]", "", scenario_name)

        name = f"{self.resource_group_prefix}-{safe_scenario}-{timestamp}"

        # Truncate if too long (max 90 chars)
        if len(name) > 90:
            # Keep prefix and timestamp, truncate scenario name
            max_scenario_len = 90 - len(self.resource_group_prefix) - len(timestamp) - 2
            safe_scenario = safe_scenario[:max_scenario_len]
            name = f"{self.resource_group_prefix}-{safe_scenario}-{timestamp}"

        return name

    def generate_deployment_name(
        self,
        scenario_name: str,
        timestamp: Optional[str] = None,
    ) -> str:
        """
        Generate deployment name.

        Args:
            scenario_name: Scenario name
            timestamp: Optional timestamp (generates new if not provided)

        Returns:
            Deployment name following pattern: neo4j-deploy-{scenario}-{timestamp}

        Example:
            >>> generate_deployment_name("standalone-v5")
            "neo4j-deploy-standalone-v5-20250116-143052"
        """
        if not timestamp:
            timestamp = get_timestamp()

        # Azure deployment names: max 64 chars
        safe_scenario = re.sub(r"[^a-zA-Z0-9-]", "", scenario_name)

        name = f"neo4j-deploy-{safe_scenario}-{timestamp}"

        # Truncate if too long (max 64 chars)
        if len(name) > 64:
            max_scenario_len = 64 - len("neo4j-deploy-") - len(timestamp) - 1
            safe_scenario = safe_scenario[:max_scenario_len]
            name = f"neo4j-deploy-{safe_scenario}-{timestamp}"

        return name
