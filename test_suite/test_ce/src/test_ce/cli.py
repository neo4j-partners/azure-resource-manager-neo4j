"""CLI entry point for the Neo4j CE integration test suite."""

import argparse
import logging
import sys

from neo4j import Driver

from test_ce.azure_helpers import run_azure_checks
from test_ce.config import StackConfig, load_all_from_results, load_from_results
from test_ce.movies_dataset import (
    MIN_EXPECTED_NODES,
    cleanup_movies,
    create_movies,
    verify_movies,
)
from test_ce.neo4j_checks import run_connectivity_tests
from test_ce.reporting import TestReporter
from test_ce.resilience import run_resilience_tests
from test_ce.wait import wait_for_neo4j

logger = logging.getLogger(__name__)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Integration tests for Neo4j Community Edition on Azure",
    )

    parser.add_argument(
        "--results",
        help="Connection JSON filename in deployments/.arm-testing/results/ (default: all scenarios)",
    )
    parser.add_argument(
        "--simple",
        action="store_true",
        help="Run only connectivity and CRUD tests",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Seconds to wait for Neo4j readiness (default: 600)",
    )
    return parser


def _log_config(config: StackConfig) -> None:
    """Log connection details for a single scenario."""
    logger.info("  Bolt : %s", config.neo4j_uri)
    logger.info("  HTTP : %s", config.browser_url)
    logger.info("  User : %s", config.username)
    if config.has_azure_context:
        logger.info("  RG   : %s", config.resource_group)
        logger.info("  VM   : %s", config.vm_name)
    logger.info("")


def _run_crud_tests(reporter: TestReporter, driver: Driver) -> None:
    """Create, verify, and clean up the Movies dataset."""
    with reporter.test("Create Movies Dataset") as ctx:
        create_movies(driver)
        ctx.pass_("dataset created")

    with reporter.test("Verify Movies Dataset") as ctx:
        count = verify_movies(driver)
        if count >= MIN_EXPECTED_NODES:
            ctx.pass_(f"{count} nodes")
        else:
            ctx.fail(f"{count} nodes, expected >= {MIN_EXPECTED_NODES}")

    cleanup_movies(driver)


def _run_simple(reporter: TestReporter, config: StackConfig) -> None:
    """Connectivity + CRUD, no Azure resource or resilience checks."""
    with config.driver() as driver:
        run_connectivity_tests(
            reporter, driver, config.browser_url, config.username, config.password
        )
        _run_crud_tests(reporter, driver)


def _run_full(
    reporter: TestReporter, config: StackConfig, timeout: int
) -> None:
    """Connectivity + Azure checks + resilience."""
    with config.driver() as driver:
        run_connectivity_tests(
            reporter, driver, config.browser_url, config.username, config.password
        )

    if config.has_azure_context:
        run_azure_checks(
            reporter,
            config.resource_group,
            config.vm_name,
            config.data_disk_id,
            config.subscription_id,
        )
        run_resilience_tests(reporter, config, timeout)
    else:
        logger.warning(
            "No Azure context (missing resource group, VM name, or "
            "subscription). Skipping resource and resilience tests."
        )
        with config.driver() as driver:
            _run_crud_tests(reporter, driver)


def _run_scenario(
    config: StackConfig, simple: bool, timeout: int
) -> int:
    """Run the test suite for a single scenario. Returns 0 on success, 1 on failure."""
    _log_config(config)

    if not wait_for_neo4j(config.browser_url, timeout=timeout):
        logger.error("Neo4j not reachable — aborting")
        return 1

    reporter = TestReporter()

    if simple:
        _run_simple(reporter, config)
    else:
        _run_full(reporter, config, timeout)

    return reporter.summary()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(message)s",
    )
    # Silence noisy Azure SDK HTTP polling logs.
    logging.getLogger("azure").setLevel(logging.WARNING)

    parser = _build_parser()
    args = parser.parse_args()

    logger.info("Neo4j CE Integration Tests")
    logger.info("")

    if args.results:
        config = load_from_results(args.results)
        sys.exit(_run_scenario(config, args.simple, args.timeout))

    scenarios = load_all_from_results()
    failed_scenarios: list[str] = []
    for i, (filename, config) in enumerate(scenarios):
        if i > 0:
            logger.info("")
        logger.info("=" * 60)
        logger.info("Scenario: %s", filename)
        logger.info("=" * 60)
        result = _run_scenario(config, args.simple, args.timeout)
        if result != 0:
            failed_scenarios.append(filename)

    passed = len(scenarios) - len(failed_scenarios)
    logger.info("")
    logger.info("=" * 60)
    logger.info("ALL SCENARIOS: %d/%d passed", passed, len(scenarios))
    if failed_scenarios:
        for name in failed_scenarios:
            logger.info("  FAILED: %s", name)
    logger.info("=" * 60)

    sys.exit(0 if not failed_scenarios else 1)
