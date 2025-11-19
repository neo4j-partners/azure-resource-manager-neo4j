"""
Deployment orchestration and parameter file generation.

Handles:
- Loading base ARM template parameters
- Applying scenario-specific overrides
- Injecting dynamic values (artifacts location, passwords)
- Parameter validation
- Generating timestamped parameter files
"""

import uuid
from pathlib import Path
from typing import Any, Optional

from rich.console import Console

from .constants import PARAMS_DIR
from .models import Settings, TestScenario
from .password import PasswordManager
from .utils import (
    construct_artifact_url,
    get_timestamp,
    load_json,
    save_json,
    validate_artifact_url,
)

console = Console()


class DeploymentEngine:
    """Orchestrates ARM template deployments."""

    def __init__(
        self,
        settings: Settings,
        base_template_dir: Path,
        deployment_type: str = "vm",
    ) -> None:
        """
        Initialize the deployment engine.

        Args:
            settings: Application settings
            base_template_dir: Path to marketplace template directory
                (e.g., marketplace/neo4j-enterprise/ or marketplace/neo4j-enterprise-aks/)
            deployment_type: Type of deployment ("vm" or "aks")
        """
        self.settings = settings
        self.base_template_dir = base_template_dir
        self.deployment_type = deployment_type
        self.password_manager = PasswordManager(settings)

        # Template files
        self.template_file = base_template_dir / "main.bicep"
        self.base_params_file = base_template_dir / "parameters.json"
        self.is_bicep = True

        # Verify template exists
        if not self.template_file.exists():
            raise FileNotFoundError(
                f"Bicep template not found: {self.template_file}\n"
                f"Ensure you're running from the repository root"
            )

        console.print(f"[dim]Using Bicep template: main.bicep ({deployment_type} deployment)[/dim]")

        if not self.base_params_file.exists():
            raise FileNotFoundError(
                f"Base parameters file not found: {self.base_params_file}\n"
                f"Ensure you're running from the repository root"
            )

    def generate_parameter_file(
        self,
        scenario: TestScenario,
        region: Optional[str] = None,
    ) -> Path:
        """
        Generate ARM template parameter file for a scenario.

        Args:
            scenario: Test scenario configuration
            region: Override region (uses default from settings if None)

        Returns:
            Path to generated parameter file

        Raises:
            ValueError: If parameters are invalid
        """
        console.print(
            f"[cyan]Generating parameters for scenario: {scenario.name}[/cyan]"
        )

        # Load base parameters
        base_params = self._load_base_parameters()

        # Get password
        password = self.password_manager.get_password(scenario.name)

        # Apply scenario overrides
        params = self._apply_scenario_overrides(
            base_params, scenario, region or self.settings.default_region
        )

        # Inject dynamic values
        params = self._inject_dynamic_values(params, password)

        # Validate parameters
        self._validate_parameters(params, scenario)

        # Generate timestamped file
        param_file_path = self._save_parameter_file(params, scenario)

        console.print(f"[green]Parameters saved to: {param_file_path}[/green]")
        return param_file_path

    def _load_base_parameters(self) -> dict[str, Any]:
        """
        Load base parameters from marketplace template.

        Returns:
            Base parameters dictionary
        """
        params = load_json(self.base_params_file)

        # ARM parameter files have a specific structure with "$schema" and "parameters"
        if "parameters" in params:
            return params
        else:
            # Old format or invalid - wrap it
            return {"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#", "contentVersion": "1.0.0.0", "parameters": params}

    def _apply_scenario_overrides(
        self,
        base_params: dict[str, Any],
        scenario: TestScenario,
        region: str,
    ) -> dict[str, Any]:
        """
        Apply scenario-specific parameter overrides.

        Args:
            base_params: Base parameters from template
            scenario: Scenario configuration
            region: Target Azure region

        Returns:
            Parameters with scenario overrides applied
        """
        params = base_params.copy()

        # Ensure parameters structure exists
        if "parameters" not in params:
            params["parameters"] = {}

        p = params["parameters"]

        # Helper to set parameter value
        def set_param(key: str, value: Any) -> None:
            if key not in p:
                p[key] = {}
            p[key]["value"] = value

        # Common parameters for all deployment types
        set_param("location", region)
        set_param("nodeCount", scenario.node_count)
        set_param("graphDatabaseVersion", scenario.graph_database_version)
        set_param("diskSize", scenario.disk_size)
        set_param("licenseType", scenario.license_type)

        # Deployment-type specific parameters
        if self.deployment_type == "vm":
            # VM-specific parameters
            set_param("vmSize", scenario.vm_size)

            # Read replicas (4.4 VM only)
            if scenario.read_replica_count > 0:
                set_param("readReplicaCount", scenario.read_replica_count)
                set_param("readReplicaVmSize", scenario.read_replica_vm_size)
                set_param("readReplicaDiskSize", scenario.read_replica_disk_size)

        elif self.deployment_type == "aks":
            # AKS-specific parameters
            if scenario.kubernetes_version:
                set_param("kubernetesVersion", scenario.kubernetes_version)
            if scenario.user_node_size:
                set_param("userNodeSize", scenario.user_node_size)
            set_param("userNodeCountMin", scenario.user_node_count_min)
            set_param("userNodeCountMax", scenario.user_node_count_max)

        # Plugins (ARM template expects "Yes"/"No" strings, not booleans)
        set_param("installGraphDataScience", "Yes" if scenario.install_graph_data_science else "No")
        if scenario.install_graph_data_science and scenario.graph_data_science_license_key != "None":
            set_param("graphDataScienceLicenseKey", scenario.graph_data_science_license_key)

        set_param("installBloom", "Yes" if scenario.install_bloom else "No")
        if scenario.install_bloom and scenario.bloom_license_key != "None":
            set_param("bloomLicenseKey", scenario.bloom_license_key)

        return params

    def _inject_dynamic_values(
        self,
        params: dict[str, Any],
        password: str,
    ) -> dict[str, Any]:
        """
        Inject dynamic values into parameters.

        Args:
            params: Parameters dictionary
            password: Admin password

        Returns:
            Parameters with dynamic values injected
        """
        p = params["parameters"]

        def set_param(key: str, value: Any) -> None:
            if key not in p:
                p[key] = {}
            p[key]["value"] = value

        # Bicep templates use embedded cloud-init (no external scripts)
        node_count = p.get("nodeCount", {}).get("value", 1)
        if node_count == 1:
            console.print("[dim]Standalone Bicep deployment - using embedded cloud-init[/dim]")
        else:
            console.print("[dim]Cluster Bicep deployment - using cloud-init[/dim]")

        # Check if using Key Vault for password management
        vault_params = self.password_manager.get_vault_parameters()

        if vault_params:
            # Using Key Vault - pass both password (for VM OS) and vault parameters (for cloud-init)
            console.print(
                f"[dim]Using Key Vault for password: {vault_params['keyVaultName']}[/dim]"
            )
            set_param("keyVaultName", vault_params["keyVaultName"])
            set_param("keyVaultResourceGroup", vault_params["keyVaultResourceGroup"])
            set_param("adminPasswordSecretName", vault_params["adminPasswordSecretName"])
            # Pass the actual password for VM OS profile (required by Azure)
            # Cloud-init will retrieve it from vault for Neo4j
            set_param("adminPassword", password)
        else:
            # Direct password mode
            set_param("adminPassword", password)

        return params

    def _validate_parameters(
        self,
        params: dict[str, Any],
        scenario: TestScenario,
    ) -> None:
        """
        Validate parameter combinations.

        Args:
            params: Generated parameters
            scenario: Scenario configuration

        Raises:
            ValueError: If parameters are invalid
        """
        p = params["parameters"]

        # Read replicas only valid with Neo4j 4.4
        if scenario.read_replica_count > 0 and scenario.graph_database_version != "4.4":
            raise ValueError(
                f"Scenario '{scenario.name}' specifies read replicas but uses "
                f"Neo4j {scenario.graph_database_version}. "
                f"Read replicas are only supported with Neo4j 4.4."
            )

        # Node count validation (already handled by Pydantic, but double-check)
        if scenario.node_count == 1:
            console.print("[dim]Deploying standalone instance (1 node)[/dim]")
        elif scenario.node_count >= 3:
            console.print(
                f"[dim]Deploying cluster with {scenario.node_count} nodes[/dim]"
            )
        else:
            raise ValueError(
                f"Invalid node count: {scenario.node_count}. "
                f"Must be 1 (standalone) or 3-10 (cluster)"
            )

        # Check required parameters are present
        required = ["location", "adminPassword"]
        for key in required:
            if key not in p or not p[key].get("value"):
                raise ValueError(f"Required parameter '{key}' is missing or empty")

    def _save_parameter_file(
        self,
        params: dict[str, Any],
        scenario: TestScenario,
    ) -> Path:
        """
        Save parameters to timestamped file.

        Args:
            params: Parameters to save
            scenario: Scenario being deployed

        Returns:
            Path to saved parameter file
        """
        timestamp = get_timestamp()
        filename = f"params-{scenario.name}-{timestamp}.json"
        file_path = PARAMS_DIR / filename

        save_json(params, file_path)

        return file_path


class DeploymentPlanner:
    """Plans and validates deployments before execution."""

    def __init__(self, settings: Settings) -> None:
        """
        Initialize the deployment planner.

        Args:
            settings: Application settings
        """
        self.settings = settings

    def generate_deployment_id(self) -> str:
        """
        Generate unique deployment ID.

        Returns:
            UUID string for deployment tracking
        """
        return str(uuid.uuid4())

    def generate_resource_group_name(
        self,
        scenario_name: str,
        timestamp: Optional[str] = None,
    ) -> str:
        """
        Generate resource group name following naming convention.

        Args:
            scenario_name: Name of the scenario
            timestamp: Optional timestamp (generates new one if None)

        Returns:
            Resource group name following pattern: {prefix}-{scenario}-{timestamp}

        Example:
            neo4j-test-standalone-v5-20250116-143052
        """
        if not timestamp:
            timestamp = get_timestamp()

        # Sanitize scenario name (replace underscores with hyphens, remove special chars)
        safe_scenario = scenario_name.replace("_", "-").replace(".", "")

        rg_name = f"{self.settings.resource_group_prefix}-{safe_scenario}-{timestamp}"

        # Azure resource group names: max 90 chars, alphanumeric and hyphens
        if len(rg_name) > 90:
            # Truncate timestamp to make it fit
            max_prefix_scenario = 90 - 16  # Leave room for -YYYYMMDD-HHMMSS
            prefix_scenario = f"{self.settings.resource_group_prefix}-{safe_scenario}"
            if len(prefix_scenario) > max_prefix_scenario:
                prefix_scenario = prefix_scenario[:max_prefix_scenario]
            rg_name = f"{prefix_scenario}-{timestamp}"

        return rg_name

    def generate_deployment_name(
        self,
        scenario_name: str,
        timestamp: Optional[str] = None,
    ) -> str:
        """
        Generate deployment name following naming convention.

        Args:
            scenario_name: Name of the scenario
            timestamp: Optional timestamp (generates new one if None)

        Returns:
            Deployment name following pattern: neo4j-deploy-{scenario}-{timestamp}

        Example:
            neo4j-deploy-standalone-v5-20250116-143052
        """
        if not timestamp:
            timestamp = get_timestamp()

        safe_scenario = scenario_name.replace("_", "-").replace(".", "")
        deploy_name = f"neo4j-deploy-{safe_scenario}-{timestamp}"

        # Azure deployment names: max 64 chars
        if len(deploy_name) > 64:
            max_scenario = 64 - 13 - 16  # "neo4j-deploy-" + timestamp
            if len(safe_scenario) > max_scenario:
                safe_scenario = safe_scenario[:max_scenario]
            deploy_name = f"neo4j-deploy-{safe_scenario}-{timestamp}"

        return deploy_name
