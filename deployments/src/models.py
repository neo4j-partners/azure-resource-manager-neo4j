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
    PROMPT = "prompt"


class DeploymentType(str, Enum):
    """Deployment platform type."""

    VM = "vm"
    AKS = "aks"
    COMMUNITY = "community"


class TestScenario(BaseModel):
    """Configuration for a single test scenario."""

    name: str = Field(..., description="Scenario name (e.g., 'standalone-v5')")

    # Deployment platform
    deployment_type: DeploymentType = Field(
        DeploymentType.VM, description="Deployment platform (vm, aks, or community)"
    )

    # Common Neo4j settings
    node_count: Literal[1, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        ..., description="Number of cluster nodes"
    )
    graph_database_version: Literal["5", "4.4"] = Field(
        ..., description="Neo4j version"
    )
    disk_size: int = Field(32, ge=32, description="Disk size in GB")
    license_type: Literal["Enterprise", "Evaluation"] = Field(
        "Evaluation", description="License type"
    )

    # VM-specific settings
    vm_size: Optional[str] = Field(None, description="Azure VM size (VM deployments)")
    read_replica_count: Literal[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        0, description="Number of read replicas (4.4 VM only)"
    )
    read_replica_vm_size: Optional[str] = Field(None, description="VM size for read replicas")
    read_replica_disk_size: int = Field(32, ge=32, description="Disk size for read replicas")

    # AKS-specific settings
    kubernetes_version: Optional[str] = Field(None, description="Kubernetes version (AKS deployments)")
    user_node_size: Optional[str] = Field(None, description="VM size for AKS user node pool")
    user_node_count_min: int = Field(1, ge=1, le=10, description="Min user nodes (AKS)")
    user_node_count_max: int = Field(10, ge=1, le=10, description="Max user nodes (AKS)")

    # Plugin settings
    install_graph_data_science: bool = Field(False, description="Install GDS plugin")
    graph_data_science_license_key: str = Field("None", description="GDS license key")
    install_bloom: bool = Field(False, description="Install Bloom")
    bloom_license_key: str = Field("None", description="Bloom license key")

    @field_validator("read_replica_count")
    @classmethod
    def validate_read_replicas(cls, v: int, info) -> int:
        """Validate that read replicas are only used with Neo4j 4.4 on Enterprise VMs."""
        data = info.data
        if v > 0:
            if data.get("deployment_type") == DeploymentType.AKS:
                raise ValueError("Read replicas are not supported on AKS deployments")
            if data.get("deployment_type") == DeploymentType.COMMUNITY:
                raise ValueError("Read replicas are not supported on Community edition")
            if data.get("graph_database_version") != "4.4":
                raise ValueError("Read replicas are only supported with Neo4j 4.4")
        return v

    @field_validator("vm_size")
    @classmethod
    def validate_vm_size(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure VM size is set for VM and Community deployments."""
        data = info.data
        deployment_type = data.get("deployment_type")
        if deployment_type in (DeploymentType.VM, DeploymentType.COMMUNITY) and not v:
            # Community gets smaller default since it's standalone only
            return "Standard_B2s" if deployment_type == DeploymentType.COMMUNITY else "Standard_E4s_v5"
        return v

    @field_validator("user_node_size")
    @classmethod
    def validate_user_node_size(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure user node size is set for AKS deployments."""
        data = info.data
        if data.get("deployment_type") == DeploymentType.AKS and not v:
            return "Standard_E4s_v5"  # Default
        return v

    @field_validator("kubernetes_version")
    @classmethod
    def validate_kubernetes_version(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure Kubernetes version is set for AKS deployments."""
        data = info.data
        if data.get("deployment_type") == DeploymentType.AKS and not v:
            return "1.30"  # Default
        return v

    @field_validator("node_count")
    @classmethod
    def validate_community_node_count(cls, v: int, info) -> int:
        """Ensure Community edition is standalone only (node_count = 1)."""
        data = info.data
        if data.get("deployment_type") == DeploymentType.COMMUNITY and v != 1:
            raise ValueError("Community edition only supports standalone deployment (node_count must be 1)")
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

    # Deployment settings
    deployment_timeout: int = Field(
        1800, description="Deployment timeout in seconds"
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
    neo4j_uri: str = Field(..., description="Neo4j connection URI (bolt:// for standalone, neo4j:// for cluster)")
    browser_url: str = Field(..., description="Neo4j Browser URL (http://...)")
    bloom_url: Optional[str] = Field(None, description="Bloom URL if installed")

    # Credentials
    username: str = Field(default="neo4j", description="Neo4j username")
    password: str = Field(..., description="Neo4j admin password")

    # License information
    license_type: str = Field(default="Evaluation", description="License type (Evaluation or Enterprise)")

    # Cluster information
    node_count: Optional[int] = Field(None, description="Number of cluster nodes (None for standalone)")

    # Deployment outputs (raw)
    outputs: dict[str, Any] = Field(..., description="Raw deployment outputs")

    # Metadata
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Timestamp when connection info was extracted"
    )
