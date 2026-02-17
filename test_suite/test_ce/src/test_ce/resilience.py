"""Persistence and resilience tests.

Validates that data survives a VM restart by:
  1. Writing a sentinel node and the Movies dataset.
  2. Restarting the VM via the Azure SDK.
  3. Waiting for Neo4j to become reachable again.
  4. Re-running connectivity tests.
  5. Verifying the sentinel and Movies data survived.
  6. Cleaning up.
"""

import logging
import uuid

from test_ce.azure_helpers import restart_vm
from test_ce.config import StackConfig
from test_ce.movies_dataset import (
    MIN_EXPECTED_NODES,
    cleanup_movies,
    create_movies,
    verify_movies,
)
from test_ce.neo4j_checks import run_connectivity_tests
from test_ce.reporting import TestReporter
from test_ce.wait import wait_for_neo4j

logger = logging.getLogger(__name__)


def run_resilience_tests(
    reporter: TestReporter,
    config: StackConfig,
    timeout: int,
) -> None:
    """Run the full persistence-through-restart test cycle."""
    test_run_id = str(uuid.uuid4())
    logger.info("Resilience test run: %s", test_run_id)

    # ------------------------------------------------------------------
    # Phase 1 — write data before restart
    # ------------------------------------------------------------------
    sentinel_ok = _write_sentinel(reporter, config, test_run_id)
    movies_ok = _create_movies(reporter, config)

    if not (sentinel_ok and movies_ok):
        logger.error("Pre-restart data writes failed; skipping restart")
        _cleanup(config, test_run_id)
        return

    # ------------------------------------------------------------------
    # Phase 2 — restart the VM
    # ------------------------------------------------------------------
    with reporter.test("VM Restart") as ctx:
        restart_vm(
            config.resource_group,
            config.vm_name,
            config.subscription_id,
        )
        ctx.pass_("restart completed")

    # ------------------------------------------------------------------
    # Phase 3 — wait for Neo4j to come back
    # ------------------------------------------------------------------
    with reporter.test("Neo4j Recovery") as ctx:
        if wait_for_neo4j(config.browser_url, timeout=timeout):
            ctx.pass_("reachable after restart")
        else:
            ctx.fail(f"not reachable after {timeout}s")
            _cleanup(config, test_run_id)
            return

    # ------------------------------------------------------------------
    # Phase 4 — re-run connectivity tests
    # ------------------------------------------------------------------
    with config.driver() as driver:
        run_connectivity_tests(
            reporter,
            driver,
            config.browser_url,
            config.username,
            config.password,
        )

    # ------------------------------------------------------------------
    # Phase 5 — verify persisted data
    # ------------------------------------------------------------------
    _verify_sentinel(reporter, config, test_run_id)
    _verify_movies(reporter, config)

    # ------------------------------------------------------------------
    # Phase 6 — cleanup
    # ------------------------------------------------------------------
    _cleanup(config, test_run_id)


# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------

def _write_sentinel(
    reporter: TestReporter, config: StackConfig, test_run_id: str
) -> bool:
    with reporter.test("Write Sentinel") as ctx:
        with config.driver() as driver:
            driver.execute_query(
                "CREATE (:Sentinel {test_run_id: $id})",
                id=test_run_id,
            )
            ctx.pass_(f"id={test_run_id[:8]}...")
    return ctx.passed


def _create_movies(reporter: TestReporter, config: StackConfig) -> bool:
    with reporter.test("Create Movies Dataset") as ctx:
        with config.driver() as driver:
            create_movies(driver)
            ctx.pass_("dataset created")
    return ctx.passed


def _verify_sentinel(
    reporter: TestReporter, config: StackConfig, test_run_id: str
) -> None:
    with reporter.test("Verify Sentinel After Restart") as ctx:
        with config.driver() as driver:
            records, _, _ = driver.execute_query(
                "MATCH (s:Sentinel {test_run_id: $id}) RETURN s",
                id=test_run_id,
            )
            if records:
                ctx.pass_("sentinel found")
            else:
                ctx.fail("sentinel node missing after restart")


def _verify_movies(reporter: TestReporter, config: StackConfig) -> None:
    with reporter.test("Verify Movies After Restart") as ctx:
        with config.driver() as driver:
            count = verify_movies(driver)
            if count >= MIN_EXPECTED_NODES:
                ctx.pass_(f"{count} nodes survived restart")
            else:
                ctx.fail(
                    f"{count} nodes, expected >= {MIN_EXPECTED_NODES}"
                )


def _cleanup(config: StackConfig, test_run_id: str) -> None:
    """Best-effort removal of test data."""
    try:
        with config.driver() as driver:
            driver.execute_query(
                "MATCH (s:Sentinel {test_run_id: $id}) DELETE s",
                id=test_run_id,
            )
            cleanup_movies(driver)
    except Exception as exc:
        logger.warning("Resilience cleanup failed (best-effort): %s", exc)
