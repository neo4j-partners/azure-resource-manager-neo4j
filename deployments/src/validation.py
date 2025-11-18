"""
ARM template validation and what-if analysis.

Provides template validation, what-if previews, and cost estimation
before deploying to Azure.
"""

import json
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field
from rich.console import Console
from rich.table import Table

from .utils import run_command

console = Console()


class ValidationResult(BaseModel):
    """Result of ARM template validation."""

    is_valid: bool = Field(..., description="Whether template is valid")
    error_code: Optional[str] = Field(None, description="Error code if invalid")
    error_message: Optional[str] = Field(None, description="Error message if invalid")
    details: Optional[dict[str, Any]] = Field(None, description="Additional details")


class WhatIfResource(BaseModel):
    """Resource from what-if analysis."""

    resource_type: str = Field(..., description="Azure resource type")
    resource_name: str = Field(..., description="Resource name")
    change_type: str = Field(..., description="Create/Modify/Delete/NoChange")
    properties: Optional[dict[str, Any]] = Field(
        None, description="Resource properties"
    )


class WhatIfResult(BaseModel):
    """Result of what-if analysis."""

    status: str = Field(..., description="Status of what-if operation")
    resources: list[WhatIfResource] = Field(
        default_factory=list, description="Resources that will be affected"
    )
    error: Optional[str] = Field(None, description="Error message if failed")


class TemplateValidator:
    """Validates ARM templates before deployment."""

    def __init__(self) -> None:
        """Initialize the template validator."""
        pass

    def validate_template(
        self,
        resource_group: str,
        template_file: Path,
        parameters_file: Path,
    ) -> ValidationResult:
        """
        Validate ARM template using Azure CLI.

        Args:
            resource_group: Resource group name (must exist)
            template_file: Path to ARM template
            parameters_file: Path to parameters file

        Returns:
            ValidationResult with validation status
        """
        console.print(
            f"[cyan]Validating template in resource group: {resource_group}[/cyan]"
        )

        try:
            result = run_command(
                f"az deployment group validate "
                f"--resource-group {resource_group} "
                f"--template-file {template_file} "
                f"--parameters @{parameters_file} "
                f"--output json",
                check=False,
            )

            # Store stdout and stderr immediately
            stdout_text = result.stdout
            stderr_text = result.stderr

            if result.returncode == 0:
                # Parse success response
                data = json.loads(stdout_text) if stdout_text else {}

                console.print("[green]✓ Template validation succeeded[/green]")
                return ValidationResult(is_valid=True, details=data)
            else:
                # Parse error response
                error_code = "ValidationFailed"
                error_message = stderr_text or "Unknown error"

                try:
                    # Try to parse stderr as JSON for structured error
                    if stderr_text:
                        error_data = json.loads(stderr_text)
                        error_code = error_data.get("error", {}).get("code", error_code)
                        error_message = error_data.get("error", {}).get(
                            "message", error_message
                        )
                except json.JSONDecodeError:
                    # If not JSON, use raw stderr
                    pass

                console.print(f"[red]✗ Template validation failed: {error_code}[/red]")
                return ValidationResult(
                    is_valid=False,
                    error_code=error_code,
                    error_message=error_message,
                )

        except Exception as e:
            console.print(f"[red]✗ Validation error: {e}[/red]")
            return ValidationResult(
                is_valid=False,
                error_code="Exception",
                error_message=str(e),
            )

    def what_if_analysis(
        self,
        resource_group: str,
        template_file: Path,
        parameters_file: Path,
    ) -> WhatIfResult:
        """
        Run what-if analysis to preview changes.

        Args:
            resource_group: Resource group name
            template_file: Path to ARM template
            parameters_file: Path to parameters file

        Returns:
            WhatIfResult with predicted changes
        """
        console.print(
            f"[cyan]Running what-if analysis for resource group: {resource_group}[/cyan]"
        )

        try:
            result = run_command(
                f"az deployment group what-if "
                f"--resource-group {resource_group} "
                f"--template-file {template_file} "
                f"--parameters @{parameters_file} "
                f"--output json",
                check=False,
            )

            if result.returncode == 0:
                # Parse what-if response
                data = json.loads(result.stdout) if result.stdout else {}

                changes = data.get("changes", [])
                resources = []

                for change in changes:
                    resource_type = change.get("resourceType", "Unknown")
                    resource_name = change.get("name", "Unknown")
                    change_type = change.get("changeType", "Unknown")

                    # Extract properties delta if available
                    delta = change.get("delta")
                    properties = {}
                    if delta:
                        properties = delta

                    resources.append(
                        WhatIfResource(
                            resource_type=resource_type,
                            resource_name=resource_name,
                            change_type=change_type,
                            properties=properties if properties else None,
                        )
                    )

                console.print(
                    f"[green]✓ What-if analysis complete: {len(resources)} changes predicted[/green]"
                )

                return WhatIfResult(status="Succeeded", resources=resources)
            else:
                error_msg = result.stderr or "Unknown error"
                console.print(f"[yellow]What-if analysis failed: {error_msg}[/yellow]")
                return WhatIfResult(status="Failed", error=error_msg)

        except Exception as e:
            console.print(f"[red]✗ What-if error: {e}[/red]")
            return WhatIfResult(status="Error", error=str(e))

    def display_what_if_results(self, what_if: WhatIfResult) -> None:
        """
        Display what-if results in formatted table.

        Args:
            what_if: What-if analysis result
        """
        if what_if.error:
            console.print(f"[yellow]What-if analysis error: {what_if.error}[/yellow]")
            return

        if not what_if.resources:
            console.print("[yellow]No changes detected[/yellow]")
            return

        # Group resources by change type
        creates = [r for r in what_if.resources if r.change_type == "Create"]
        modifies = [r for r in what_if.resources if r.change_type == "Modify"]
        deletes = [r for r in what_if.resources if r.change_type == "Delete"]

        # Display creates
        if creates:
            table = Table(title="Resources to Create", show_header=True)
            table.add_column("Resource Type", style="cyan")
            table.add_column("Name", style="white")

            for resource in creates:
                table.add_row(resource.resource_type, resource.resource_name)

            console.print(table)
            console.print()

        # Display modifications
        if modifies:
            table = Table(title="Resources to Modify", show_header=True)
            table.add_column("Resource Type", style="yellow")
            table.add_column("Name", style="white")

            for resource in modifies:
                table.add_row(resource.resource_type, resource.resource_name)

            console.print(table)
            console.print()

        # Display deletions
        if deletes:
            table = Table(title="Resources to Delete", show_header=True)
            table.add_column("Resource Type", style="red")
            table.add_column("Name", style="white")

            for resource in deletes:
                table.add_row(resource.resource_type, resource.resource_name)

            console.print(table)
            console.print()

        # Summary
        console.print(f"[bold]Summary:[/bold]")
        console.print(f"  [green]Create:[/green] {len(creates)}")
        console.print(f"  [yellow]Modify:[/yellow] {len(modifies)}")
        console.print(f"  [red]Delete:[/red] {len(deletes)}")


class CostEstimator:
    """Estimates deployment costs based on resources."""

    # Simple pricing table (USD per hour) - should be updated with real pricing
    PRICING = {
        "Standard_E4s_v5": 0.252,  # 4 vCPU, 32 GB RAM
        "Standard_E8s_v5": 0.504,  # 8 vCPU, 64 GB RAM
        "Standard_D4s_v5": 0.192,  # 4 vCPU, 16 GB RAM
        "managed_disk_p10": 0.068,  # 128 GB Premium SSD
        "managed_disk_p15": 0.135,  # 256 GB Premium SSD
        "load_balancer_standard": 0.025,  # Standard Load Balancer
        "public_ip_standard": 0.005,  # Standard Public IP
    }

    def __init__(self) -> None:
        """Initialize the cost estimator."""
        pass

    def estimate_cost(
        self,
        node_count: int,
        vm_size: str,
        disk_size: int,
        duration_hours: int = 1,
    ) -> dict[str, Any]:
        """
        Estimate deployment cost.

        Args:
            node_count: Number of VMs
            vm_size: Azure VM size
            disk_size: Disk size in GB
            duration_hours: Estimated runtime in hours

        Returns:
            Cost breakdown dictionary
        """
        costs = {}

        # VM costs
        vm_hourly = self.PRICING.get(vm_size, 0.25)  # Default estimate
        vm_cost = vm_hourly * node_count * duration_hours
        costs["vms"] = {
            "count": node_count,
            "hourly_rate": vm_hourly,
            "total": vm_cost,
        }

        # Disk costs (estimate based on size)
        disk_hourly = 0.068 if disk_size <= 128 else 0.135
        disk_cost = disk_hourly * node_count * duration_hours
        costs["disks"] = {
            "count": node_count,
            "hourly_rate": disk_hourly,
            "total": disk_cost,
        }

        # Load balancer (for clusters)
        if node_count >= 3:
            lb_hourly = self.PRICING["load_balancer_standard"]
            lb_cost = lb_hourly * duration_hours
            costs["load_balancer"] = {
                "count": 1,
                "hourly_rate": lb_hourly,
                "total": lb_cost,
            }

        # Public IP
        ip_hourly = self.PRICING["public_ip_standard"]
        ip_count = 1 if node_count == 1 else 1  # One public IP for LB or standalone
        ip_cost = ip_hourly * ip_count * duration_hours
        costs["public_ip"] = {
            "count": ip_count,
            "hourly_rate": ip_hourly,
            "total": ip_cost,
        }

        # Calculate total
        total_cost = sum(item["total"] for item in costs.values())

        return {
            "duration_hours": duration_hours,
            "breakdown": costs,
            "total": total_cost,
        }

    def display_cost_estimate(self, estimate: dict[str, Any], max_cost: Optional[float] = None) -> bool:
        """
        Display cost estimate in formatted table.

        Args:
            estimate: Cost estimate dictionary
            max_cost: Maximum allowed cost (optional)

        Returns:
            True if within cost limit, False otherwise
        """
        table = Table(title=f"Cost Estimate ({estimate['duration_hours']}h runtime)")
        table.add_column("Resource", style="cyan")
        table.add_column("Count", style="white")
        table.add_column("Hourly Rate", style="white")
        table.add_column("Total", style="green")

        for resource, data in estimate["breakdown"].items():
            resource_name = resource.replace("_", " ").title()
            table.add_row(
                resource_name,
                str(data["count"]),
                f"${data['hourly_rate']:.3f}/hr",
                f"${data['total']:.2f}",
            )

        console.print(table)
        console.print(f"\n[bold]Total Estimated Cost:[/bold] [green]${estimate['total']:.2f}[/green]")

        if max_cost and estimate["total"] > max_cost:
            console.print(
                f"[red]⚠ Cost estimate ${estimate['total']:.2f} exceeds limit ${max_cost:.2f}[/red]"
            )
            return False

        return True
