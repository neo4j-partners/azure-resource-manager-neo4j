"""Test reporting and result tracking."""

import logging
import time
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class TestResult:
    """Result of a single test execution."""

    name: str
    passed: bool
    message: str
    duration: float


class TestContext:
    """Yielded by TestReporter.test() to record pass/fail from inside the test body."""

    def __init__(self) -> None:
        self.passed: bool = False
        self.message: str = "no verdict recorded"

    def pass_(self, message: str = "OK") -> None:
        self.passed = True
        self.message = message

    def fail(self, message: str) -> None:
        self.passed = False
        self.message = message


@dataclass
class TestReporter:
    """Collects test results and prints a summary."""

    results: list[TestResult] = field(default_factory=list)
    start_time: float = field(default_factory=time.time)

    @contextmanager
    def test(self, name: str) -> Generator[TestContext, None, None]:
        """Context manager that wraps a single test execution.

        Catches exceptions and records them as failures so the suite
        continues running even when individual tests raise.
        """
        ctx = TestContext()
        t0 = time.time()
        try:
            logger.info("Running: %s", name)
            yield ctx
        except Exception as exc:
            ctx.fail(str(exc))
        finally:
            duration = time.time() - t0
            result = TestResult(
                name=name,
                passed=ctx.passed,
                message=ctx.message,
                duration=duration,
            )
            self.results.append(result)
            status = "PASS" if result.passed else "FAIL"
            logger.info("  %s  %s (%.1fs)", status, result.message, duration)

    def summary(self) -> int:
        """Print a summary table and return the exit code.

        Returns 0 if all tests passed, 1 if any test failed.
        """
        total_duration = time.time() - self.start_time
        passed = sum(1 for r in self.results if r.passed)
        failed = sum(1 for r in self.results if not r.passed)
        total = len(self.results)

        logger.info("")
        logger.info("=" * 60)
        logger.info("TEST SUMMARY")
        logger.info("=" * 60)

        for r in self.results:
            status = "PASS" if r.passed else "FAIL"
            logger.info("  [%s]  %-40s  %.1fs", status, r.name, r.duration)
            if not r.passed and r.message:
                logger.info("         %s", r.message)

        logger.info("-" * 60)
        logger.info(
            "  %d passed, %d failed, %d total  (%.1fs)",
            passed,
            failed,
            total,
            total_duration,
        )
        logger.info("=" * 60)

        return 0 if failed == 0 else 1
