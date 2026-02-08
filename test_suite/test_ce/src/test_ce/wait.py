"""Readiness polling for Neo4j HTTP endpoint."""

import logging
import time

import requests

logger = logging.getLogger(__name__)


def wait_for_neo4j(
    browser_url: str,
    timeout: int = 300,
    interval: int = 10,
) -> bool:
    """Poll *browser_url* until Neo4j responds with HTTP 200.

    Returns True when Neo4j is ready, False on timeout.
    """
    deadline = time.time() + timeout
    logger.info("Waiting for Neo4j at %s (timeout %ds)", browser_url, timeout)

    while time.time() < deadline:
        try:
            resp = requests.get(browser_url, timeout=5)
            if resp.status_code == 200:
                logger.info("Neo4j is ready")
                return True
        except requests.RequestException:
            pass

        remaining = max(0, int(deadline - time.time()))
        logger.info("  Not ready yet, %ds remaining", remaining)
        time.sleep(interval)

    logger.error("Timed out waiting for Neo4j after %ds", timeout)
    return False
