"""
Utility functions for the ARM template testing suite.
"""

import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

import yaml
from rich.console import Console

from .constants import TIMESTAMP_FORMAT

console = Console()


def run_command(
    command: str | list[str],
    capture_output: bool = True,
    check: bool = True,
    shell: bool = False,
) -> subprocess.CompletedProcess:
    """
    Run a shell command and return the result.

    Args:
        command: Command to run (string or list of arguments)
        capture_output: Whether to capture stdout/stderr
        check: Whether to raise exception on non-zero exit
        shell: Whether to run through shell

    Returns:
        CompletedProcess instance with command results
    """
    if isinstance(command, str) and not shell:
        command = command.split()

    return subprocess.run(
        command,
        capture_output=capture_output,
        text=True,
        check=check,
        shell=shell,
    )


def get_git_branch() -> Optional[str]:
    """
    Get the current Git branch name.

    Returns:
        Branch name or None if not in a Git repository
    """
    try:
        result = run_command("git rev-parse --abbrev-ref HEAD", check=False)
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception as e:
        console.print(f"[yellow]Warning: Could not detect Git branch: {e}[/yellow]")
    return None


def get_git_remote_url() -> Optional[str]:
    """
    Get the Git remote URL.

    Returns:
        Remote URL or None if not available
    """
    try:
        result = run_command("git remote get-url origin", check=False)
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def parse_github_url(url: str) -> Optional[tuple[str, str]]:
    """
    Parse GitHub organization and repository name from URL.

    Args:
        url: GitHub URL (https or git format)

    Returns:
        Tuple of (organization, repository) or None if not a GitHub URL
    """
    if not url:
        return None

    # Handle HTTPS URLs: https://github.com/org/repo.git
    if "github.com" in url:
        parts = url.rstrip("/").rstrip(".git").split("/")
        if len(parts) >= 2:
            return parts[-2], parts[-1]

    return None


def get_timestamp() -> str:
    """
    Get current timestamp in standard format.

    Returns:
        Formatted timestamp string
    """
    return datetime.now().strftime(TIMESTAMP_FORMAT)


def ensure_directory(path: Path) -> None:
    """
    Ensure a directory exists, creating it if necessary.

    Args:
        path: Directory path to create
    """
    path.mkdir(parents=True, exist_ok=True)


def load_yaml(path: Path) -> dict[str, Any]:
    """
    Load YAML file.

    Args:
        path: Path to YAML file

    Returns:
        Parsed YAML content

    Raises:
        FileNotFoundError: If file doesn't exist
        yaml.YAMLError: If file is invalid YAML
    """
    with open(path, "r") as f:
        return yaml.safe_load(f)


def save_yaml(data: dict[str, Any], path: Path) -> None:
    """
    Save data to YAML file.

    Args:
        data: Data to save
        path: Path to save to
    """
    ensure_directory(path.parent)
    with open(path, "w") as f:
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)


def load_json(path: Path) -> dict[str, Any]:
    """
    Load JSON file.

    Args:
        path: Path to JSON file

    Returns:
        Parsed JSON content
    """
    with open(path, "r") as f:
        return json.load(f)


def save_json(data: dict[str, Any], path: Path, indent: int = 2) -> None:
    """
    Save data to JSON file.

    Args:
        data: Data to save
        path: Path to save to
        indent: JSON indentation level
    """
    ensure_directory(path.parent)
    with open(path, "w") as f:
        json.dump(data, f, indent=indent, default=str)


def get_az_account_info() -> Optional[dict[str, Any]]:
    """
    Get Azure account information using az CLI.

    Returns:
        Account information dict or None if az CLI not available
    """
    try:
        result = run_command("az account show", check=False)
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception as e:
        console.print(f"[red]Error getting Azure account info: {e}[/red]")
    return None


def get_az_default_location() -> Optional[str]:
    """
    Get the default Azure location from az CLI configuration.

    Returns:
        Default location or None if not configured
    """
    try:
        result = run_command("az configure --list-defaults", check=False)
        if result.returncode == 0:
            # Parse the output which is in format: name=value
            for line in result.stdout.strip().split('\n'):
                if line.strip().startswith('location'):
                    # Format is: location    value    global
                    parts = line.split()
                    if len(parts) >= 2:
                        return parts[1]
    except Exception:
        pass

    # Fallback: try to get from account info (some accounts have a home region)
    try:
        account_info = get_az_account_info()
        if account_info and 'tenantDefaultDomain' in account_info:
            # Try to infer region from tenant (not reliable but worth a try)
            pass
    except Exception:
        pass

    return None


def get_git_user_email() -> Optional[str]:
    """
    Get Git user email configuration.

    Returns:
        User email or None if not configured
    """
    try:
        result = run_command("git config user.email", check=False)
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def construct_artifact_url(
    branch: Optional[str] = None,
    org: Optional[str] = None,
    repo: Optional[str] = None,
) -> Optional[str]:
    """
    Construct GitHub raw content URL for ARM template artifacts.

    Args:
        branch: Git branch name (defaults to current branch)
        org: GitHub organization (defaults to detected from remote)
        repo: GitHub repository (defaults to detected from remote)

    Returns:
        Artifact URL with trailing slash, or None if cannot construct

    Example:
        https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/main/
    """
    # Get branch if not provided
    if not branch:
        branch = get_git_branch()
        if not branch:
            return None

    # Get org/repo from remote if not provided
    if not org or not repo:
        remote_url = get_git_remote_url()
        if remote_url:
            parsed = parse_github_url(remote_url)
            if parsed:
                detected_org, detected_repo = parsed
                org = org or detected_org
                repo = repo or detected_repo

    if not org or not repo:
        return None

    # Construct URL with trailing slash
    url = f"https://raw.githubusercontent.com/{org}/{repo}/{branch}/"
    return url


def validate_artifact_url(url: str, check_script: bool = True) -> tuple[bool, Optional[str]]:
    """
    Validate that artifact URL is accessible and scripts exist.

    Args:
        url: Artifact URL to validate (should end with /)
        check_script: Whether to check if node.sh script exists

    Returns:
        Tuple of (is_valid, error_message)
        is_valid is True if URL is accessible, False otherwise
        error_message is None if valid, otherwise contains error description
    """
    import requests

    # Ensure URL ends with /
    if not url.endswith("/"):
        url = url + "/"

    if not check_script:
        # Just validate URL format
        if url.startswith("https://raw.githubusercontent.com/"):
            return True, None
        else:
            return False, "URL must be a raw.githubusercontent.com URL"

    # Check if installation script exists
    script_url = f"{url}scripts/neo4j-enterprise/node.sh"

    try:
        response = requests.head(script_url, timeout=10)

        if response.status_code == 200:
            return True, None
        elif response.status_code == 404:
            return False, (
                f"Installation script not found at {script_url}\n"
                f"This may mean:\n"
                f"  1. The branch hasn't been pushed to GitHub yet\n"
                f"  2. The scripts directory doesn't exist on this branch\n"
                f"  3. The repository/organization name is incorrect"
            )
        else:
            return False, (
                f"Unexpected response code {response.status_code} "
                f"when checking {script_url}"
            )

    except requests.exceptions.Timeout:
        return False, (
            f"Timeout while checking {script_url}\n"
            f"Check your internet connection or try again later"
        )
    except requests.exceptions.RequestException as e:
        return False, f"Network error while validating artifact URL: {e}"
