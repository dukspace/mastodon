"""Exercise branch selection using local Git repositories and a fake Docker CLI."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("deploy.sh").resolve()


class DeploymentTest(unittest.TestCase):
    def git(self, directory, *args):
        return subprocess.check_output(
            ["git", "-C", str(directory), *args], text=True, stderr=subprocess.DEVNULL
        ).strip()

    def identity(self, directory):
        self.git(directory, "config", "user.name", "Deployment test")
        self.git(directory, "config", "user.email", "deployment@example.invalid")
        self.git(directory, "config", "commit.gpgsign", "false")
        self.git(directory, "config", "core.hooksPath", "/dev/null")

    def commit(self, directory):
        self.git(directory, "add", ".")
        self.git(directory, "commit", "-m", "Fixture\n\nCo-Authored-by: Codex <noreply@openai.com>")
        return self.git(directory, "rev-parse", "HEAD")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="staging-deploy-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote.git"
        self.seed = self.root / "seed"
        self.checkout = self.root / "checkout"
        self.git(self.root, "init", "--bare", str(self.remote))
        self.git(self.root, "init", "-b", "production", str(self.seed))
        self.identity(self.seed)
        (self.seed / "docker-compose.yml").write_text("services: {}\n")
        (self.seed / ".gitignore").write_text(".env.production\n")
        self.previous = self.commit(self.seed)
        self.git(self.seed, "remote", "add", "origin", str(self.remote))
        self.git(self.seed, "push", "origin", "production")
        self.git(self.root, "clone", "--single-branch", "--branch", "production", str(self.remote), str(self.checkout))
        self.identity(self.checkout)
        self.git(self.checkout, "branch", "staging")
        (self.checkout / ".env.production").write_text("TEST_ONLY=true\n")
        self.git(self.seed, "switch", "-c", "staging")
        (self.seed / "candidate.txt").write_text("candidate\n")
        self.candidate = self.commit(self.seed)
        self.git(self.seed, "push", "origin", "staging")
        self.log = self.root / "docker.jsonl"
        self.output = self.root / "github-output"
        binary = self.root / "bin"
        binary.mkdir()
        docker = binary / "docker"
        docker.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["TEST_DOCKER_LOG"], "a") as log:
    log.write(json.dumps([os.environ.get("MASTODON_IMAGE_TAG"), sys.argv[1:]]) + "\\n")
if sys.argv[-1] == 'printf %s "$SOURCE_COMMIT"':
    print(os.environ["TEST_DEPLOY_SHA"], end="")
''')
        docker.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            PATH=str(binary) + os.pathsep + self.env["PATH"],
            TEST_DOCKER_LOG=str(self.log),
            TEST_DEPLOY_SHA=self.candidate,
            GITHUB_OUTPUT=str(self.output),
        )

    def deploy(self, sha):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.checkout), sha],
            env=self.env, capture_output=True, text=True, timeout=15,
        )

    def test_staging_tip_deploys_from_production_only_clone(self):
        result = self.deploy(self.candidate)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current"), "staging")
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), self.candidate)
        self.assertEqual(self.git(self.checkout, "rev-parse", "production"), self.previous)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertTrue(calls)
        self.assertTrue(all(tag == "sha-" + self.candidate for tag, _ in calls))
        self.assertIn("deployed=true", self.output.read_text())

    def test_superseded_commit_never_calls_docker(self):
        result = self.deploy(self.previous)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping superseded deployment", result.stdout)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current"), "production")
        self.assertFalse(self.log.exists())
        self.assertEqual(self.output.read_text(), "deployed=false\n")

    def test_tracked_local_changes_are_preserved(self):
        compose = self.checkout / "docker-compose.yml"
        compose.write_text("local change\n")
        result = self.deploy(self.candidate)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(compose.read_text(), "local change\n")
        self.assertFalse(self.log.exists())

    def test_divergent_staging_branch_is_not_reset(self):
        self.git(self.checkout, "switch", "staging")
        (self.checkout / "local.txt").write_text("local commit\n")
        local_sha = self.commit(self.checkout)
        result = self.deploy(self.candidate)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), local_sha)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
