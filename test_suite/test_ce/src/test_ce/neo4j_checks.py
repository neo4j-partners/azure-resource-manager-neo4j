"""Connectivity tests for a Neo4j deployment."""

import logging

import requests
from neo4j import Driver

from test_ce.reporting import TestReporter

logger = logging.getLogger(__name__)


def run_connectivity_tests(
    reporter: TestReporter,
    driver: Driver,
    browser_url: str,
    username: str,
    password: str,
) -> None:
    """Run all connectivity tests and record results in *reporter*."""
    _check_http_api(reporter, browser_url)
    _check_http_auth(reporter, browser_url, username, password)
    _check_bolt(reporter, driver)
    _check_apoc(reporter, driver)
    _check_edition(reporter, driver)


def _check_http_api(reporter: TestReporter, browser_url: str) -> None:
    with reporter.test("HTTP API") as ctx:
        resp = requests.get(browser_url, timeout=10)
        data = resp.json()
        if "neo4j_version" in data:
            ctx.pass_(f"version {data['neo4j_version']}")
        else:
            ctx.fail("Response missing neo4j_version field")


def _check_http_auth(
    reporter: TestReporter,
    browser_url: str,
    username: str,
    password: str,
) -> None:
    with reporter.test("HTTP Authentication") as ctx:
        url = f"{browser_url}/db/neo4j/tx/commit"
        payload = {"statements": [{"statement": "RETURN 1"}]}
        resp = requests.post(
            url, json=payload, auth=(username, password), timeout=10
        )
        if resp.status_code == 200:
            ctx.pass_(f"HTTP {resp.status_code}")
        else:
            ctx.fail(f"HTTP {resp.status_code}")


def _check_bolt(reporter: TestReporter, driver: Driver) -> None:
    with reporter.test("Bolt Connectivity") as ctx:
        records, _, _ = driver.execute_query("RETURN 1 AS n")
        if not records:
            ctx.fail("Empty result set")
        elif records[0]["n"] == 1:
            ctx.pass_("RETURN 1 = 1")
        else:
            ctx.fail(f"Unexpected result: {records[0]['n']}")


def _check_apoc(reporter: TestReporter, driver: Driver) -> None:
    with reporter.test("APOC Plugin") as ctx:
        records, _, _ = driver.execute_query(
            "RETURN apoc.version() AS v"
        )
        if not records:
            ctx.fail("Empty result set")
        elif records[0]["v"]:
            ctx.pass_(f"APOC {records[0]['v']}")
        else:
            ctx.fail("No APOC version returned")


def _check_edition(reporter: TestReporter, driver: Driver) -> None:
    with reporter.test("Community Edition") as ctx:
        records, _, _ = driver.execute_query(
            "CALL dbms.components() YIELD edition RETURN edition"
        )
        if not records:
            ctx.fail("Empty result set")
        elif records[0]["edition"].lower() == "community":
            ctx.pass_(f"edition={records[0]['edition']}")
        else:
            ctx.fail(f"Expected community, got {records[0]['edition']}")
