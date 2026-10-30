#!/usr/bin/env python3
"""Offline checks that unsafe workflow edits are refused by the smoke checker."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "scripts/check-workflow.sh"
WORKFLOWS = ROOT / ".github/workflows"
ENV_PUBLISH = (WORKFLOWS / "env-publish.yml").read_text()


class WorkflowChecks(unittest.TestCase):
    def check_text(self, text):
        with tempfile.TemporaryDirectory(prefix="workflow-check-") as directory:
            workflow = Path(directory) / "workflow.yml"
            workflow.write_text(text)
            return subprocess.run(
                ["bash", str(CHECKER), str(workflow)],
                capture_output=True,
                text=True,
                check=False,
            )

    def assert_rejected(self, text, check_name):
        result = self.check_text(text)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"FAIL  {check_name}", result.stdout)
        # A failed check must not stop the script before its final summary.
        self.assertRegex(result.stdout, r"\d+ passed, [1-9]\d* failed\n$")

    def test_default_checks_both_workflows(self):
        result = subprocess.run(
            ["bash", str(CHECKER)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("release.yml", result.stdout)
        self.assertIn("env-publish.yml", result.stdout)

    def test_each_workflow_passes_explicitly(self):
        for name in ("release.yml", "env-publish.yml"):
            with self.subTest(workflow=name):
                result = self.check_text((WORKFLOWS / name).read_text())
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_submit_cannot_use_npm_trusted_environment(self):
        for environment in ("cust-a", "cust-b"):
            with self.subTest(environment=environment):
                self.assert_rejected(
                    ENV_PUBLISH.replace(
                        "environment: coderoot-submit", f"environment: {environment}"
                    ),
                    "submit uses coderoot-submit",
                )

    def test_secrets_cannot_be_referenced(self):
        for job in ("pack", "submit"):
            with self.subTest(job=job):
                self.assert_rejected(
                    ENV_PUBLISH.replace(
                        f"\n  {job}:\n",
                        f"\n  {job}:\n    env:\n      KEY: ${{{{ secrets['OTHER_KEY'] }}}}\n",
                    ),
                    "no secrets referenced",
                )

    def test_submit_must_run_the_public_action(self):
        self.assert_rejected(
            ENV_PUBLISH.replace(
                "uses: coderoot-eth/action@", "uses: VitroTech/coderoot-action@"
            ),
            "submit runs the public CodeRoot Action",
        )

    def test_local_action_is_refused(self):
        self.assert_rejected(
            ENV_PUBLISH + "      - uses: ./coderoot-action\n",
            "no local actions",
        )

    def test_release_bytes_cannot_be_uploaded(self):
        self.assert_rejected(
            ENV_PUBLISH
            + "      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9\n"
            + "        with:\n          path: release\n",
            "no workflow artifact transfer",
        )

    def test_external_uses_must_stay_pinned(self):
        for pinned, floating in (
            ("@11bd71901bbe5b1630ceea73d27597364c9af683", "@v4"),
            ("@b223537eb81026b90477e4e02e70d9c4fcdf7d95", "@v1"),
        ):
            with self.subTest(ref=floating):
                self.assert_rejected(
                    ENV_PUBLISH.replace(pinned, floating), "uses references pinned"
                )

    def test_npm_token_cannot_reach_submit(self):
        self.assert_rejected(
            ENV_PUBLISH.replace("  submit:\n", "  submit:\n    env:\n      NPM_TOKEN: unsafe\n"),
            "no npm credential",
        )

    def test_inputs_cannot_be_interpolated_into_shell(self):
        self.assert_rejected(
            ENV_PUBLISH.replace("set -euo pipefail", 'echo "${{ inputs.version }}"', 1),
            "inputs reach shell via env only",
        )


if __name__ == "__main__":
    unittest.main()
