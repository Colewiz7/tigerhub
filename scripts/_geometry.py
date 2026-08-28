"""Print the TigerHub window geometry in the form grim -g expects."""

import json
import sys

CLASS = "dev.colewiz.tigerhub"

clients = [c for c in json.load(sys.stdin) if c.get("class") == CLASS]
if not clients:
    sys.exit(1)

client = clients[0]
x, y = client["at"]
width, height = client["size"]
print(f"{x},{y} {width}x{height}")
