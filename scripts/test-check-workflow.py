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

    def test_action_key_cannot_reach_other_jobs(self):
        self.assert_rejected(
            ENV_PUBLISH.replace(
                "  pack:\n",
                "  pack:\n    env:\n      ACTION_KEY: ${{ secrets.CODEROOT_ACTION_KEY }}\n",
            ),
            "no secrets outside submit",
        )

    def test_additional_secret_cannot_reach_submit(self):
        self.assert_rejected(
            ENV_PUBLISH + "          token: ${{ secrets['OTHER_KEY'] }}\n",
            "only the Action checkout references a secret",
        )

    def test_key_cannot_be_printed_by_submit(self):
        self.assert_rejected(
            ENV_PUBLISH + '      - run: echo "${{ secrets.CODEROOT_ACTION_KEY }}"\n',
            "only the Action checkout references a secret",
        )

    def test_private_action_cannot_be_uploaded(self):
        self.assert_rejected(
            ENV_PUBLISH
            + "      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9\n"
            + "        with:\n          path: coderoot-action\n",
            "no workflow artifact transfer",
        )

    def test_external_uses_must_stay_pinned(self):
        self.assert_rejected(
            ENV_PUBLISH.replace("@11bd71901bbe5b1630ceea73d27597364c9af683", "@v4"),
            "uses references pinned or approved local Action",
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
