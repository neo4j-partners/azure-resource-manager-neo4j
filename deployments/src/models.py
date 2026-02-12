"""
Pydantic models for configuration and state management.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import TYPE_CHECKING, Any, Literal, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

if TYPE_CHECKING:
    from .deployment import DeploymentEngine
    from .orchestrator import DeploymentOrchestrator


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


class Edition(str, Enum):
    """Neo4j edition, determines which marketplace template to use."""

    ENTERPRISE = "enterprise"
    COMMUNITY = "community"

    @property
    def template_dirname(self) -> str:
        """Marketplace template directory name for this edition."""
        return {
            Edition.ENTERPRISE: "neo4j-enterprise",
            Edition.COMMUNITY: "neo4j-ce",
        }[self]

    @classmethod
    def from_license_type(cls, license_type: str) -> Edition:
        """
        Map a scenario license_type to the corresponding edition.

        Args:
            license_type: "Community", "Enterprise", or "Evaluation"

        Returns:
            Edition enum value
        """
        if license_type == "Community":
            return cls.COMMUNITY
        return cls.ENTERPRISE


@dataclass
class PreparedScenario:
    """A scenario with its generated parameter file and deployment engine."""

    scenario: TestScenario
    parameter_file: Path
    engine: DeploymentEngine


@dataclass
class ScenarioDeployment:
    """Tracks a submitted deployment with its associated engine and orchestrator."""

    state: DeploymentState
    engine: DeploymentEngine
    orchestrator: DeploymentOrchestrator


class TestScenario(BaseModel):
    """Configuration for a single test scenario."""

    name: str = Field(..., description="Scenario name (e.g., 'standalone-lts')")

    # Deployment platform
    deployment_type: DeploymentType = Field(
        DeploymentType.VM, description="Deployment platform"
    )

    # Common Neo4j settings
    node_count: Literal[1, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        ..., description="Number of cluster nodes"
    )
    graph_database_version: Literal["latest", "5", "4.4"] = Field(
        ..., description="Neo4j version ('latest' for CalVer 2025.x/2026.x, '5' for LTS, '4.4' for legacy)"
    )
    disk_size: int = Field(32, ge=32, description="Disk size in GB")
    license_type: Literal["Enterprise", "Evaluation", "Community"] = Field(
        "Evaluation", description="License type"
    )

    # Region override (optional, defaults to settings.default_region)
    region: Optional[str] = Field(None, description="Region override for this scenario")

    # VM-specific settings
    vm_size: Optional[str] = Field(None, description="Azure VM size")
    read_replica_count: Literal[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] = Field(
        0, description="Number of read replicas (4.4 only)"
    )
    read_replica_vm_size: Optional[str] = Field(None, description="VM size for read replicas")
    read_replica_disk_size: int = Field(32, ge=32, description="Disk size for read replicas")

    # Plugin settings
    install_graph_data_science: bool = Field(False, description="Install GDS plugin")
    graph_data_science_license_key: str = Field("None", description="GDS license key")
    install_bloom: bool = Field(False, description="Install Bloom")
    bloom_license_key: str = Field("None", description="Bloom license key")

    @field_validator("read_replica_count")
    @classmethod
    def validate_read_replicas(cls, v: int, info) -> int:
        """Validate that read replicas are only used with Neo4j 4.4."""
        data = info.data
        if v > 0:
            if data.get("graph_database_version") != "4.4":
                raise ValueError("Read replicas are only supported with Neo4j 4.4")
        return v

    @model_validator(mode="after")
    def validate_community_constraints(self) -> "TestScenario":
        """Validate Community Edition constraints after all fields are set."""
        if self.license_type == "Community":
            if self.node_count != 1:
                raise ValueError("Community Edition only supports standalone deployment (node_count=1)")
            if self.graph_database_version not in ("latest", "5"):
                raise ValueError("Community Edition only supports 'latest' (CalVer) or '5' (LTS)")
            if self.install_graph_data_science:
                raise ValueError("Graph Data Science is not available in Community Edition")
            if self.install_bloom:
                raise ValueError("Bloom is not available in Community Edition")
        return self

    @field_validator("vm_size")
    @classmethod
    def validate_vm_size(cls, v: Optional[str], info) -> Optional[str]:
        """Ensure VM size is set for deployments."""
        if not v:
            return "Standard_E4s_v5"
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

    # Pre-publish image overrides
    ce_use_test_image: bool = Field(
        False,
        description="Use standard RHEL 9 image instead of neo4j-ce-vm marketplace image. "
        "Set to true for pre-publish testing before the marketplace offer is available.",
    )
    ce_gallery_image_id: Optional[str] = Field(
        None,
        description="Azure Compute Gallery image version resource ID for CE deployments. "
        "When set, deploys from this gallery image instead of the marketplace image. "
        "Example: /subscriptions/.../galleries/neo4jmarketplace/images/neo4j-ce-vm/versions/1.1.0",
    )


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
    license_type: str = Field(default="Evaluation", description="License type (Evaluation, Enterprise, or Community)")

    # Cluster information
    node_count: Optional[int] = Field(None, description="Number of cluster nodes (None for standalone)")

    # Deployment outputs (raw)
    outputs: dict[str, Any] = Field(..., description="Raw deployment outputs")

    # Metadata
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Timestamp when connection info was extracted"
    )
