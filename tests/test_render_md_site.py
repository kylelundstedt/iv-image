import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class RenderMarkdownSiteTests(unittest.TestCase):
    def setUp(self):
        if shutil.which("apex") is None:
            self.skipTest("apex is not installed")

    def test_apex_preserves_known_regression_cases(self):
        repo_root = Path(__file__).resolve().parents[1]
        renderer = repo_root / "bin" / "render-md-site"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            long_line = "a" * 4096 + "END-OF-LONG-LINE"
            (root / "index.md").write_text(
                "# Site\n\n"
                "## Verb contracts [TBD — define schema]\n\n"
                f"{long_line}\n\n"
                "- **Item.** Some text here.\n\n"
                "  Intro:\n\n"
                "  | A | B |\n"
                "  | --- | --- |\n"
                "  | 1 | 2 |\n\n"
                "  The relationship is **WAP : table writes :: AVE : executions**.\n\n"
                "::: {#home-recent}\nRecent content.\n:::\n",
                encoding="utf-8",
            )
            subprocess.run(
                [str(renderer), str(root)], check=True, env=os.environ.copy()
            )
            html = (root / "_site" / "index.html").read_text(encoding="utf-8")

        self.assertIn("Verb contracts [TBD — define schema]", html)
        self.assertIn("END-OF-LONG-LINE", html)
        self.assertIn("<table>", html)
        self.assertIn("<strong>WAP : table writes :: AVE : executions</strong>", html)
        self.assertIn('<div id="home-recent">', html)


if __name__ == "__main__":
    unittest.main()
