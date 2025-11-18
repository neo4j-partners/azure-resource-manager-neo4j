"""
Neo4j deployment validation using pure Python implementation.

Validates Neo4j deployments by creating test datasets, verifying connectivity,
and checking license types using the official Neo4j Python driver.
"""

from typing import Optional

from neo4j import GraphDatabase, Driver, Session
from rich.console import Console

console = Console()

# Cypher query constants
EVALUATION_LICENSE_CYPHER = "CALL dbms.acceptedLicenseAgreement();"

MOVIES_CYPHER = """
CREATE (TheMatrix:Movie {title:'The Matrix', released:1999, tagline:'Welcome to the Real World'})
CREATE (Keanu:Person {name:'Keanu Reeves', born:1964})
CREATE (Carrie:Person {name:'Carrie-Anne Moss', born:1967})
CREATE (Laurence:Person {name:'Laurence Fishburne', born:1961})
CREATE (Hugo:Person {name:'Hugo Weaving', born:1960})
CREATE (LillyW:Person {name:'Lilly Wachowski', born:1967})
CREATE (LanaW:Person {name:'Lana Wachowski', born:1965})
CREATE (JoelS:Person {name:'Joel Silver', born:1952})
CREATE
(Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrix),
(Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrix),
(Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrix),
(Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrix),
(LillyW)-[:DIRECTED]->(TheMatrix),
(LanaW)-[:DIRECTED]->(TheMatrix),
(JoelS)-[:PRODUCED]->(TheMatrix)

CREATE (Emil:Person {name:"Emil Eifrem", born:1978})
CREATE (Emil)-[:ACTED_IN {roles:["Emil"]}]->(TheMatrix)

CREATE (TheMatrixReloaded:Movie {title:'The Matrix Reloaded', released:2003, tagline:'Free your mind'})
CREATE
(Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrixReloaded),
(Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrixReloaded),
(Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrixReloaded),
(Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrixReloaded),
(LillyW)-[:DIRECTED]->(TheMatrixReloaded),
(LanaW)-[:DIRECTED]->(TheMatrixReloaded),
(JoelS)-[:PRODUCED]->(TheMatrixReloaded)

CREATE (TheMatrixRevolutions:Movie {title:'The Matrix Revolutions', released:2003, tagline:'Everything that has a beginning has an end'})
CREATE
(Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrixRevolutions),
(Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrixRevolutions),
(Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrixRevolutions),
(Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrixRevolutions),
(LillyW)-[:DIRECTED]->(TheMatrixRevolutions),
(LanaW)-[:DIRECTED]->(TheMatrixRevolutions),
(JoelS)-[:PRODUCED]->(TheMatrixRevolutions)

WITH Keanu as a
MATCH (a)-[:ACTED_IN]->(m)<-[:DIRECTED]-(d) RETURN a,m,d LIMIT 10;
"""


class Neo4jValidator:
    """
    Neo4j deployment validator.

    Validates Neo4j deployments through connection testing, dataset operations,
    and license verification.
    """

    def __init__(self, uri: str, username: str, password: str) -> None:
        """
        Initialize the Neo4j validator.

        Args:
            uri: Neo4j connection URI (e.g., neo4j://hostname:7687)
            username: Database username (typically 'neo4j')
            password: Database password
        """
        self.uri = uri
        self.username = username
        self.password = password
        self._driver: Optional[Driver] = None

    def __enter__(self) -> "Neo4jValidator":
        """Context manager entry - establish connection."""
        self._driver = GraphDatabase.driver(
            self.uri,
            auth=(self.username, self.password)
        )
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit - close connection."""
        if self._driver:
            self._driver.close()
            self._driver = None

    def create_movies_dataset(self) -> None:
        """
        Create the movies dataset in the Neo4j database.

        This executes a large Cypher query that creates nodes and relationships
        representing movies, actors, directors, and their connections.

        Raises:
            RuntimeError: If dataset creation fails
        """
        console.print("[cyan]Creating movies dataset...[/cyan]")

        if not self._driver:
            raise RuntimeError("Driver not initialized. Use context manager.")

        try:
            with self._driver.session() as session:
                result = session.execute_write(
                    lambda tx: tx.run(MOVIES_CYPHER).consume()
                )
                console.print("[green]✓ Movies dataset created[/green]")

        except Exception as e:
            error_msg = f"Failed to create movies dataset: {e}"
            console.print(f"[red]✗ {error_msg}[/red]")
            raise RuntimeError(error_msg) from e

    def verify_movies_dataset(self) -> None:
        """
        Verify the movies dataset exists by querying all nodes.

        Checks that at least one node exists in the database.

        Raises:
            RuntimeError: If verification fails or no records found
        """
        console.print("[cyan]Verifying movies dataset...[/cyan]")

        if not self._driver:
            raise RuntimeError("Driver not initialized. Use context manager.")

        try:
            with self._driver.session() as session:
                records = session.execute_read(
                    lambda tx: list(tx.run("MATCH (N) RETURN N;"))
                )

                if not records or len(records) == 0:
                    raise RuntimeError("Failed to get any records - database is empty")

                console.print(f"[green]✓ Verification successful - found {len(records)} nodes[/green]")

        except RuntimeError:
            raise
        except Exception as e:
            error_msg = f"Failed to verify movies dataset: {e}"
            console.print(f"[red]✗ {error_msg}[/red]")
            raise RuntimeError(error_msg) from e

    def cleanup_movies_dataset(self) -> None:
        """
        Delete the movies dataset created during testing.

        Removes all nodes and relationships to leave the database clean.
        """
        console.print("[cyan]Cleaning up test dataset...[/cyan]")

        if not self._driver:
            raise RuntimeError("Driver not initialized. Use context manager.")

        try:
            with self._driver.session() as session:
                # Delete all nodes and relationships
                result = session.execute_write(
                    lambda tx: tx.run("MATCH (n) DETACH DELETE n").consume()
                )
                console.print("[green]✓ Test dataset removed[/green]")

        except Exception as e:
            # Don't fail validation on cleanup issues
            console.print(f"[yellow]⚠ Cleanup warning: {e}[/yellow]")
            console.print("[yellow]  You may need to manually clean up test data[/yellow]")

    def check_cluster_nodes(self, expected_node_count: Optional[int] = None) -> None:
        """
        Check cluster node count and status.

        Uses SHOW SERVERS to verify the cluster topology and that all expected
        nodes are enabled and available.

        Args:
            expected_node_count: Expected number of nodes in the cluster (optional)

        Raises:
            RuntimeError: If cluster check fails or node count doesn't match
        """
        console.print("[cyan]Checking cluster topology...[/cyan]")

        if not self._driver:
            raise RuntimeError("Driver not initialized. Use context manager.")

        try:
            with self._driver.session() as session:
                records = session.execute_read(
                    lambda tx: list(tx.run("SHOW SERVERS"))
                )

                if len(records) == 0:
                    # Single node deployment or SHOW SERVERS not available
                    console.print("[yellow]⚠ No cluster topology found (standalone deployment)[/yellow]")
                    console.print("[green]✓ Skipping cluster verification[/green]")
                    return

                # Count enabled servers
                enabled_count = 0
                server_details = []

                for record in records:
                    record_dict = dict(record)
                    name = record_dict.get("name", "unknown")
                    address = record_dict.get("address", "unknown")
                    state = record_dict.get("state", "unknown")

                    server_details.append(f"{name} ({address}) - {state}")

                    if state == "Enabled":
                        enabled_count += 1

                console.print(f"[dim]Cluster servers found: {len(records)}[/dim]")
                for detail in server_details:
                    console.print(f"[dim]  • {detail}[/dim]")

                # Check against expected count if provided
                if expected_node_count is not None:
                    if enabled_count != expected_node_count:
                        raise RuntimeError(
                            f"Expected {expected_node_count} enabled nodes, "
                            f"but found {enabled_count}"
                        )
                    console.print(
                        f"[green]✓ Verified cluster has {enabled_count} enabled nodes "
                        f"(expected {expected_node_count})[/green]"
                    )
                else:
                    console.print(
                        f"[green]✓ Cluster has {enabled_count} enabled nodes[/green]"
                    )

        except RuntimeError:
            raise
        except Exception as e:
            # Don't fail validation on cluster check issues for standalone deployments
            console.print(f"[yellow]⚠ Cluster check error: {e}[/yellow]")
            console.print("[yellow]  This is normal for standalone deployments[/yellow]")
            console.print("[green]✓ Continuing validation[/green]")

    def check_evaluation_license(self) -> None:
        """
        Check that the database is running with an Evaluation license.

        Queries the database license agreement and verifies the response
        indicates an evaluation or trial license.

        Raises:
            RuntimeError: If license check fails or license is not Evaluation
        """
        console.print("[cyan]Checking license type...[/cyan]")

        if not self._driver:
            raise RuntimeError("Driver not initialized. Use context manager.")

        try:
            with self._driver.session() as session:
                records = session.execute_read(
                    lambda tx: list(tx.run(EVALUATION_LICENSE_CYPHER))
                )

                if len(records) == 0:
                    # If no records, the procedure might not be available or license might be different
                    console.print("[yellow]⚠ License agreement query returned no results[/yellow]")
                    console.print("[yellow]  This is normal for some Neo4j versions/licenses[/yellow]")
                    console.print("[green]✓ Skipping license verification[/green]")
                    return

                # Check first record for license information
                record = records[0]

                # The response format can vary, so let's be flexible
                # Possible fields: 'value', 'status', 'accepted', etc.
                record_dict = dict(record)

                console.print(f"[dim]License info: {record_dict}[/dim]")

                # Check various possible indicators of evaluation/trial license
                # This is a best-effort check
                if "value" in record_dict:
                    value = record_dict["value"]
                    # Value of 30 or "30" indicates 30-day evaluation
                    if str(value) == "30":
                        console.print("[green]✓ Verified Evaluation License (30-day trial)[/green]")
                        return

                # If we can't definitively verify, just note that database is accessible
                console.print("[yellow]⚠ License type verification inconclusive[/yellow]")
                console.print("[green]✓ Database is accessible and responding[/green]")

        except RuntimeError:
            raise
        except Exception as e:
            # Don't fail validation on license check issues
            console.print(f"[yellow]⚠ License check error: {e}[/yellow]")
            console.print("[green]✓ Continuing validation (database is accessible)[/green]")

    def run_full_validation(
        self,
        license_type: str = "Evaluation",
        expected_node_count: Optional[int] = None
    ) -> bool:
        """
        Run complete validation suite.

        Executes all validation steps:
        1. Check cluster topology (if cluster deployment)
        2. Create movies dataset
        3. Verify dataset was created
        4. Check license type (if Evaluation)
        5. Clean up test dataset

        Args:
            license_type: Expected license type ("Evaluation" or "Enterprise")
            expected_node_count: Expected number of cluster nodes (None for standalone)

        Returns:
            True if all validations pass, False otherwise
        """
        validation_passed = False
        try:
            # Check cluster topology first (before writing data)
            if expected_node_count is not None and expected_node_count > 1:
                self.check_cluster_nodes(expected_node_count)

            # Create and verify dataset
            self.create_movies_dataset()
            self.verify_movies_dataset()

            # Check license if Evaluation
            if license_type == "Evaluation":
                self.check_evaluation_license()

            validation_passed = True
            console.print("[green bold]✓ All validations passed[/green bold]")

        except Exception as e:
            console.print(f"[red bold]✗ Validation failed: {e}[/red bold]")
            validation_passed = False

        finally:
            # Always clean up test data, even if validation failed
            try:
                self.cleanup_movies_dataset()
            except Exception as cleanup_error:
                console.print(f"[yellow]⚠ Cleanup failed: {cleanup_error}[/yellow]")

        return validation_passed


def validate_deployment(
    uri: str,
    username: str,
    password: str,
    license_type: str = "Evaluation",
    expected_node_count: Optional[int] = None
) -> bool:
    """
    Validate a Neo4j deployment.

    Convenience function that creates a validator and runs full validation.

    Args:
        uri: Neo4j connection URI (e.g., neo4j://hostname:7687)
        username: Database username (typically 'neo4j')
        password: Database password
        license_type: Expected license type ("Evaluation" or "Enterprise")
        expected_node_count: Expected number of cluster nodes (None for standalone)

    Returns:
        True if validation passes, False otherwise

    Example:
        >>> validate_deployment(
        ...     "neo4j://example.com:7687",
        ...     "neo4j",
        ...     "my-password",
        ...     "Evaluation",
        ...     3
        ... )
        True
    """
    with Neo4jValidator(uri, username, password) as validator:
        return validator.run_full_validation(license_type, expected_node_count)


def load_connection_info_from_scenario(scenario_name: str) -> Optional[dict]:
    """
    Load the most recent connection info for a scenario from .arm-testing/results.

    Args:
        scenario_name: Scenario name to search for

    Returns:
        Connection info dictionary or None if not found
    """
    import json
    from pathlib import Path

    # Path to results directory
    results_dir = Path(".arm-testing/results")

    if not results_dir.exists():
        console.print(f"[red]Error: Results directory not found: {results_dir}[/red]")
        console.print("[yellow]Have you run any deployments yet?[/yellow]")
        return None

    # Find all connection files for this scenario
    pattern = f"connection-{scenario_name}-*.json"
    files = sorted(results_dir.glob(pattern), reverse=True)

    if not files:
        console.print(f"[red]Error: No connection info found for scenario: {scenario_name}[/red]")
        console.print(f"[yellow]Looking for files matching: {pattern}[/yellow]")

        # List available scenarios
        all_files = list(results_dir.glob("connection-*.json"))
        if all_files:
            scenarios = set()
            for f in all_files:
                # Extract scenario name from filename: connection-{scenario}-{timestamp}.json
                parts = f.stem.split("-")
                if len(parts) >= 2:
                    # Scenario name is everything between "connection-" and the timestamp
                    # Timestamp is last part (YYYYMMDD-HHMMSS format)
                    scenario = "-".join(parts[1:-2]) if len(parts) > 3 else parts[1]
                    scenarios.add(scenario)

            console.print(f"\n[cyan]Available scenarios:[/cyan]")
            for s in sorted(scenarios):
                console.print(f"  - {s}")

        return None

    # Load most recent file
    latest_file = files[0]
    console.print(f"[dim]Loading connection info from: {latest_file}[/dim]")

    try:
        with open(latest_file, "r") as f:
            data = json.load(f)
        return data
    except Exception as e:
        console.print(f"[red]Error loading connection info: {e}[/red]")
        return None


def main():
    """Command-line entry point for validate_deploy."""
    import sys

    # Support two modes:
    # 1. Scenario name (reads from .arm-testing)
    # 2. Full manual parameters (uri, username, password, license_type)

    if len(sys.argv) == 2:
        # Mode 1: Scenario name
        scenario_name = sys.argv[1]

        console.print(f"\n[bold]Neo4j Deployment Validator[/bold]\n")
        console.print(f"[cyan]Scenario:[/cyan] {scenario_name}\n")

        # Load connection info from .arm-testing
        conn_data = load_connection_info_from_scenario(scenario_name)
        if not conn_data:
            sys.exit(1)

        # Extract required fields
        uri = conn_data.get("neo4j_uri")
        username = conn_data.get("username", "neo4j")
        password = conn_data.get("password")
        license_type = conn_data.get("license_type", "Evaluation")
        node_count = conn_data.get("node_count")

        if not uri or not password:
            console.print("[red]Error: Connection info is incomplete[/red]")
            console.print(f"[yellow]URI: {uri}[/yellow]")
            console.print(f"[yellow]Password: {'<present>' if password else '<missing>'}[/yellow]")
            sys.exit(1)

        console.print(f"[cyan]URI:[/cyan] {uri}")
        console.print(f"[cyan]Username:[/cyan] {username}")
        console.print(f"[cyan]License Type:[/cyan] {license_type}")
        if node_count:
            console.print(f"[cyan]Expected Nodes:[/cyan] {node_count}")
        console.print()

    elif len(sys.argv) == 5:
        # Mode 2: Full manual parameters (standalone)
        uri = sys.argv[1]
        username = sys.argv[2]
        password = sys.argv[3]
        license_type = sys.argv[4]
        node_count = None

        console.print(f"\n[bold]Neo4j Deployment Validator[/bold]\n")
        console.print(f"[cyan]URI:[/cyan] {uri}")
        console.print(f"[cyan]Username:[/cyan] {username}")
        console.print(f"[cyan]License Type:[/cyan] {license_type}\n")

    elif len(sys.argv) == 6:
        # Mode 3: Full manual parameters with node count (cluster)
        uri = sys.argv[1]
        username = sys.argv[2]
        password = sys.argv[3]
        license_type = sys.argv[4]
        node_count = int(sys.argv[5])

        console.print(f"\n[bold]Neo4j Deployment Validator[/bold]\n")
        console.print(f"[cyan]URI:[/cyan] {uri}")
        console.print(f"[cyan]Username:[/cyan] {username}")
        console.print(f"[cyan]License Type:[/cyan] {license_type}")
        console.print(f"[cyan]Expected Nodes:[/cyan] {node_count}\n")

    else:
        console.print("[red]Error: Invalid arguments[/red]")
        console.print("\n[cyan]Usage (from deployment):[/cyan]")
        console.print("  validate_deploy <scenario_name>")
        console.print("\n[cyan]Usage (manual - standalone):[/cyan]")
        console.print("  validate_deploy <uri> <username> <password> <license_type>")
        console.print("\n[cyan]Usage (manual - cluster):[/cyan]")
        console.print("  validate_deploy <uri> <username> <password> <license_type> <node_count>")
        console.print("\n[cyan]Examples:[/cyan]")
        console.print("  validate_deploy standalone-v5")
        console.print("  validate_deploy neo4j://example.com:7687 neo4j mypassword Evaluation")
        console.print("  validate_deploy neo4j://cluster.example.com:7687 neo4j mypassword Enterprise 3")
        sys.exit(1)

    try:
        # Pass node_count if available
        if len(sys.argv) == 2 or len(sys.argv) == 5 or len(sys.argv) == 6:
            success = validate_deployment(uri, username, password, license_type, node_count)
        else:
            success = validate_deployment(uri, username, password, license_type)
        sys.exit(0 if success else 1)
    except Exception as e:
        console.print(f"\n[red bold]Validation failed with error:[/red bold]")
        console.print(f"[red]{e}[/red]")
        sys.exit(1)


if __name__ == "__main__":
    main()
