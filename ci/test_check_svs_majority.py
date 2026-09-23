"""Run with python3 -m unittest discover -s ci -p 'test_*.py'."""

import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).with_name("check-svs-majority.sh")


class MajorityTests(unittest.TestCase):
    def run_check(self, versions, status=200):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/info":
                    self.send_response(200)
                    body = '{"sv":{"version":"1.0.0"}}'
                else:
                    self.send_response(status)
                    body = versions
                self.end_headers()
                self.wfile.write(body.encode("utf-8"))

            def log_message(self, *args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                with tempfile.TemporaryDirectory() as temp:
                    output = Path(temp) / "output"
                    env = dict(os.environ, GITHUB_OUTPUT=output.as_posix())
                    result = subprocess.run(
                        ["bash", SCRIPT.as_posix(), "TestNet",
                         f"http://127.0.0.1:{server.server_port}"],
                        env=env, capture_output=True, text=True, timeout=15,
                    )
                    value = output.read_text(encoding="utf-8") if output.exists() else ""
                    return result, value
            finally:
                server.shutdown()
                thread.join()

    def test_two_thirds_majority(self):
        result, output = self.run_check("name,url,version\na,a,1.0.0\nb,b,1.0.0\nc,c,0.9.0\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "svs_majority=true\n")

    def test_insufficient_majority(self):
        result, output = self.run_check("name,url,version\na,a,1.0.0\nb,b,0.9.0\nc,c,0.9.0\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "svs_majority=false\n")

    def test_http_error_with_parseable_body(self):
        result, output = self.run_check("name,url,version\na,a,1.0.0\n", status=503)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(output, "svs_majority=false\n")

    def test_empty_version_list(self):
        for versions in ("", "name,url,version\n"):
            with self.subTest(versions=versions):
                result, output = self.run_check(versions)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertEqual(output, "svs_majority=false\n")


if __name__ == "__main__":
    unittest.main()
