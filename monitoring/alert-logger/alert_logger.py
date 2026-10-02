"""Récepteur webhook minimal pour Alertmanager : écrit chaque alerte sur stdout.
Les logs du conteneur sont ensuite collectés par Promtail et visibles dans Loki.
"""

import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        try:
            payload = json.loads(body)
            for alert in payload.get("alerts", []):
                print(
                    json.dumps(
                        {
                            "event": "alert",
                            "status": alert.get("status"),
                            "alertname": alert.get("labels", {}).get("alertname"),
                            "severity": alert.get("labels", {}).get("severity"),
                            "summary": alert.get("annotations", {}).get("summary"),
                            "startsAt": alert.get("startsAt"),
                        }
                    ),
                    flush=True,
                )
        except json.JSONDecodeError:
            print("payload invalide", flush=True)

        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):  # silence les logs HTTP par défaut
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 5001), Handler).serve_forever()
