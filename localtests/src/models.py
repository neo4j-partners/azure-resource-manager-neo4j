"""
Pydantic models for configuration and state management.
"""

from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field, field_validator


class CleanupMode(str, Enum):
    """Cleanup modes for resource management."""

    IMMEDIATE = "immediate"
    ON_SUCCESS = "on-success"
    MANUAL = "manual"
    SCHEDULED = "scheduled"


class PasswordStrategy(str, Enum):
    """Password provisioning strategies."""

    GENERATE = "generate"
    ENVIRONMENT = "environment"
    AZURE_KEYVAULT = "azure-keyvault"
    PROMPT = "prompt"


class TestScenario(BaseModel):
    """Configuration for a single test scenario."""

    name: str = Field(..., description="Scenario name (e.g., 'standalone-v5')")
    node_count: Literal[1, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        ..., description="Number of cluster nodes"
    )
    graph_database_version: Literal["5", "4.4"] = Field(
        ..., description="Neo4j version"
    )
    vm_size: str = Field("Standard_E4s_v5", description="Azure VM size")
    disk_size: int = Field(32, ge=32, description="Disk size in GB")
    read_replica_count: Literal[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        0, description="Number of read replicas (4.4 only)"
    )
    read_replica_vm_size: str = Field("Standard_E4s_v5", description="VM size for read replicas")
    read_replica_disk_size: int = Field(32, ge=32, description="Disk size for read replicas")
    license_type: Literal["Enterprise", "Evaluation"] = Field(
        "Evaluation", description="License type"
    )
    install_graph_data_science: bool = Field(False, description="Install GDS plugin")
    graph_data_science_license_key: str = Field("None", description="GDS license key")
    install_bloom: bool = Field(False, description="Install Bloom")
    bloom_license_key: str = Field("None", description="Bloom license key")

    @field_validator("read_replica_count")
    @classmethod
    def validate_read_replicas(cls, v: int, info) -> int:
        """Validate that read replicas are only used with Neo4j 4.4."""
        if v > 0 and info.data.get("graph_database_version") != "4.4":
            raise ValueError("Read replicas are only supported with Neo4j 4.4")
        return v


class Settings(BaseModel):
    """Main configuration settings."""

    # Azure settings
    subscription_id: str = Field(..., description="Azure subscription ID")
    subscription_name: str = Field(..., description="Azure subscription name")
    default_region: str = Field("westeurope", description="Default Azure region")

    # Resource naming
    resource_group_prefix: str = Field(
        "neo4j-test", description="Prefix for resource group names"
    )

    # Cleanup settings
    default_cleanup_mode: CleanupMode = Field(
        CleanupMode.ON_SUCCESS, description="Default cleanup behavior"
    )

    # Cost settings
    max_cost_per_deployment: Optional[float] = Field(
        None, description="Maximum estimated cost in USD"
    )

    # Git settings
    auto_detect_branch: bool = Field(
        True, description="Automatically detect Git branch for artifact location"
    )
    repository_org: Optional[str] = Field(None, description="GitHub organization")
    repository_name: Optional[str] = Field(None, description="GitHub repository name")

    # Password settings
    password_strategy: PasswordStrategy = Field(
        PasswordStrategy.GENERATE, description="How to provide admin password"
    )
    azure_keyvault_name: Optional[str] = Field(
        None, description="Azure Key Vault name (if using keyvault strategy)"
    )

    # Deployment settings
    deployment_timeout: int = Field(
        1800, description="Deployment timeout in seconds"
    )
    max_parallel_deployments: int = Field(
        3, ge=1, le=10, description="Maximum concurrent deployments"
    )

    # User info
    owner_email: str = Field(..., description="Owner email for resource tagging")


class ScenarioCollection(BaseModel):
    """Collection of test scenarios."""

    scenarios: list[TestScenario] = Field(..., description="List of test scenarios")


class DeploymentState(BaseModel):
    """State tracking for a deployment."""

    deployment_id: str = Field(..., description="Unique deployment identifier")
    resource_group_name: str = Field(..., description="Azure resource group name")
    deployment_name: str = Field(..., description="Azure deployment name")
    scenario_name: str = Field(..., description="Scenario name")
    git_branch: str = Field(..., description="Git branch used")
    parameter_file_path: str = Field(..., description="Path to parameter file")
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc), description="Creation timestamp"
    )
    expires_at: Optional[datetime] = Field(None, description="Expiration timestamp")
    cleanup_mode: CleanupMode = Field(..., description="Cleanup mode")
    status: Literal["pending", "deploying", "succeeded", "failed", "deleted"] = Field(
        "pending", description="Deployment status"
    )
    test_status: Optional[Literal["passed", "failed", "not-run"]] = Field(
        None, description="Test result status"
    )
    test_result: Optional[dict[str, Any]] = Field(
        None, description="Full test result data"
    )


class ActiveDeployments(BaseModel):
    """Collection of active deployments."""

    deployments: list[DeploymentState] = Field(
        default_factory=list, description="List of active deployments"
    )


class ConnectionInfo(BaseModel):
    """Connection information for a deployed Neo4j instance."""

    deployment_id: str = Field(..., description="Deployment ID")
    scenario_name: str = Field(..., description="Scenario name")
    resource_group: str = Field(..., description="Resource group name")

    # Connection details
    neo4j_uri: str = Field(..., description="Neo4j protocol connection URI (neo4j://...)")
    browser_url: str = Field(..., description="Neo4j Browser URL (http://...)")
    bloom_url: Optional[str] = Field(None, description="Bloom URL if installed")

    # Deployment outputs (raw)
    outputs: dict[str, Any] = Field(..., description="Raw deployment outputs")

    # Metadata
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Timestamp when connection info was extracted"
    )


class TestResult(BaseModel):
    """Test result from neo4jtester execution."""

    deployment_id: str = Field(..., description="Deployment ID that was tested")
    scenario_name: str = Field(..., description="Scenario name")

    # Test results
    passed: bool = Field(..., description="Whether the test passed")
    exit_code: int = Field(..., description="neo4jtester exit code")
    output: str = Field(..., description="Test output (truncated)")
    log_file: Optional[str] = Field(None, description="Path to full log file")

    # Metadata
    tested_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Timestamp when test was executed"
    )
