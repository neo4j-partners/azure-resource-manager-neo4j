"""
Constants and default values for the Neo4j Azure deployment tools.
"""

from pathlib import Path
from typing import Final

# Directory paths (relative to deployments/)
ARM_TESTING_DIR: Final[Path] = Path(".arm-testing")
CONFIG_DIR: Final[Path] = ARM_TESTING_DIR / "config"
STATE_DIR: Final[Path] = ARM_TESTING_DIR / "state"
PARAMS_DIR: Final[Path] = ARM_TESTING_DIR / "params"
RESULTS_DIR: Final[Path] = ARM_TESTING_DIR / "results"
LOGS_DIR: Final[Path] = ARM_TESTING_DIR / "logs"
TEMPLATES_DIR: Final[Path] = ARM_TESTING_DIR / "templates"

# Configuration files
SETTINGS_FILE: Final[Path] = CONFIG_DIR / "settings.yaml"
SCENARIOS_FILE: Final[Path] = CONFIG_DIR / "scenarios.yaml"

# CE region categories for the setup wizard's region picker.
# See marketplace/neo4j-ce/ARCHITECTURE.md for regional availability research.
CE_ZONAL_REGIONS: Final[list[str]] = [
    # Regions with availability zones where Eds_v6 + PremiumV2_LRS + zone 1 all work
    # pickZones() returns ['1'] → PremiumV2_LRS + zone 1 pinning
    "eastus2",       # Default test region
    "eastus",
    "centralus",
    "westus3",
    "northeurope",
    "uksouth",
    "swedencentral",
    "japaneast",
    "japanwest",
    "australiaeast",
]

CE_NONZONAL_REGIONS: Final[list[str]] = [
    # Eds_v6 available but no availability zones
    # pickZones() returns [] → Premium_LRS + no zone pinning
    "northcentralus",
    "westus",
    "canadaeast",
    "ukwest",
]

CE_RESTRICTED_REGIONS: Final[list[str]] = [
    # Eds_v6 exists with zones but subscription-restricted (needs quota request)
    "westeurope",
    "southcentralus",
    "westus2",
]

# Resource naming patterns
RESOURCE_GROUP_PREFIX: Final[str] = "neo4j-test"
DEPLOYMENT_PREFIX: Final[str] = "neo4j-deploy"

# Default VM sizes for cost-effective testing
DEFAULT_VM_SIZES: Final[dict[str, str]] = {
    "standalone": "Standard_E4s_v5",
    "cluster": "Standard_E4s_v5",
    "performance": "Standard_E8s_v5",
}

# Neo4j versions
NEO4J_VERSIONS: Final[list[str]] = ["latest", "5"]

# License types
LICENSE_TYPES: Final[list[str]] = ["Enterprise", "Evaluation", "Community"]

# Cleanup modes
CLEANUP_MODES: Final[list[str]] = ["immediate", "on-success", "manual", "scheduled"]

# Default cleanup mode
DEFAULT_CLEANUP_MODE: Final[str] = "on-success"

# Default deployment timeout (in seconds)
DEFAULT_DEPLOYMENT_TIMEOUT: Final[int] = 1800  # 30 minutes

# Azure resource tags
RESOURCE_TAGS: Final[dict[str, str]] = {
    "purpose": "neo4j-deployment",
    "managed-by": "neo4j-deploy",
}

# Timestamp format
TIMESTAMP_FORMAT: Final[str] = "%Y%m%d-%H%M%S"

# GitHub repository URL pattern
GITHUB_RAW_URL_PATTERN: Final[str] = (
    "https://raw.githubusercontent.com/{org}/{repo}/{branch}/"
)

# Password options
PASSWORD_OPTIONS: Final[list[str]] = [
    "generate",
    "environment",
    "prompt",
]
