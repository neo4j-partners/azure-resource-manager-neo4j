#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "neo4j>=5.25.0",
# ]
# ///
"""
Simple Neo4j validation script using uv.

Usage:
    uv run validate.py <url> <username> <password>

Example:
    uv run validate.py bolt://localhost:7687 neo4j mypassword
"""

import sys
from neo4j import GraphDatabase


def validate_neo4j(uri: str, username: str, password: str) -> bool:
    """Connect to Neo4j and run a simple validation query."""

    print(f"🔗 Connecting to Neo4j at {uri}...")

    try:
        # Create driver
        driver = GraphDatabase.driver(uri, auth=(username, password))

        # Verify connectivity
        driver.verify_connectivity()
        print("✓ Connection successful")

        # Run a simple query
        with driver.session() as session:
            # Create a test node
            result = session.run(
                "CREATE (n:ValidationTest {timestamp: datetime(), message: $msg}) RETURN n",
                msg="Hello from uv validate.py!"
            )
            node = result.single()["n"]
            print(f"✓ Created test node: {node['message']}")

            # Count nodes
            result = session.run("MATCH (n) RETURN count(n) as count")
            count = result.single()["count"]
            print(f"✓ Database has {count} nodes")

            # Clean up test node
            session.run("MATCH (n:ValidationTest) DELETE n")
            print("✓ Cleaned up test node")

        # Close driver
        driver.close()

        print("\n✅ All validation checks passed!")
        return True

    except Exception as e:
        print(f"\n❌ Validation failed: {e}")
        return False


def main():
    """Main entry point."""

    if len(sys.argv) != 4:
        print("Usage: uv run validate.py <url> <username> <password>")
        print("\nExample:")
        print("  uv run validate.py bolt://localhost:7687 neo4j mypassword")
        print("\nOr with neo4j:// protocol:")
        print("  uv run validate.py neo4j://localhost:7687 neo4j mypassword")
        sys.exit(1)

    uri = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    # Validate Neo4j
    success = validate_neo4j(uri, username, password)

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
