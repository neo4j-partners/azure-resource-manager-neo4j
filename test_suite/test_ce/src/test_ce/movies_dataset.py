"""Movies dataset for CRUD validation.

Functions in this module are *pure* — they do not interact with the
TestReporter.  The caller wraps them in ``reporter.test()`` as needed,
which allows reuse from both the simple-mode CRUD tests and the
resilience tests without double-reporting.
"""

import logging

from neo4j import Driver

logger = logging.getLogger(__name__)

MOVIES_CYPHER = """
CREATE (TheMatrix:Movie {title:'The Matrix', released:1999,
        tagline:'Welcome to the Real World'})
CREATE (TheMatrixReloaded:Movie {title:'The Matrix Reloaded', released:2003,
        tagline:'Free your mind'})
CREATE (TheMatrixRevolutions:Movie {title:'The Matrix Revolutions', released:2003,
        tagline:'Everything that has a beginning has an end'})
CREATE (Keanu:Person {name:'Keanu Reeves', born:1964})
CREATE (Carrie:Person {name:'Carrie-Anne Moss', born:1967})
CREATE (Laurence:Person {name:'Laurence Fishburne', born:1961})
CREATE (Hugo:Person {name:'Hugo Weaving', born:1960})
CREATE (LillyW:Person {name:'Lilly Wachowski', born:1967})
CREATE (LanaW:Person {name:'Lana Wachowski', born:1965})
CREATE (JoelS:Person {name:'Joel Silver', born:1952})
CREATE (EmilE:Person {name:'Emil Eifrem', born:1978})
CREATE
  (Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrix),
  (Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrix),
  (Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrix),
  (Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrix),
  (LillyW)-[:DIRECTED]->(TheMatrix),
  (LanaW)-[:DIRECTED]->(TheMatrix),
  (JoelS)-[:PRODUCED]->(TheMatrix),
  (EmilE)-[:ACTED_IN {roles:['Emil']}]->(TheMatrix),
  (Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrixReloaded),
  (Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrixReloaded),
  (Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrixReloaded),
  (Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrixReloaded),
  (LillyW)-[:DIRECTED]->(TheMatrixReloaded),
  (LanaW)-[:DIRECTED]->(TheMatrixReloaded),
  (JoelS)-[:PRODUCED]->(TheMatrixReloaded),
  (Keanu)-[:ACTED_IN {roles:['Neo']}]->(TheMatrixRevolutions),
  (Carrie)-[:ACTED_IN {roles:['Trinity']}]->(TheMatrixRevolutions),
  (Laurence)-[:ACTED_IN {roles:['Morpheus']}]->(TheMatrixRevolutions),
  (Hugo)-[:ACTED_IN {roles:['Agent Smith']}]->(TheMatrixRevolutions),
  (LillyW)-[:DIRECTED]->(TheMatrixRevolutions),
  (LanaW)-[:DIRECTED]->(TheMatrixRevolutions),
  (JoelS)-[:PRODUCED]->(TheMatrixRevolutions)
"""

MIN_EXPECTED_NODES = 11


def create_movies(driver: Driver) -> None:
    """Create the Movies graph dataset. Raises on failure."""
    driver.execute_query(MOVIES_CYPHER)
    logger.info("Movies dataset created")


def verify_movies(driver: Driver) -> int:
    """Return the count of Movie + Person nodes. Raises on failure."""
    records, _, _ = driver.execute_query(
        "MATCH (n) WHERE n:Movie OR n:Person RETURN count(n) AS cnt"
    )
    count: int = records[0]["cnt"]
    logger.info("Movies dataset contains %d nodes", count)
    return count


def cleanup_movies(driver: Driver) -> None:
    """Delete all Movie and Person nodes. Best-effort, never raises."""
    try:
        driver.execute_query(
            "MATCH (n) WHERE n:Movie OR n:Person DETACH DELETE n"
        )
        logger.info("Movies dataset cleaned up")
    except Exception as exc:
        logger.warning("Movies cleanup failed (best-effort): %s", exc)
