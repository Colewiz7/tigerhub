"""Pretty print /health/sources for `scripts/dev status`."""

import json
import sys

data = json.load(sys.stdin)
print("  sources:")
for source in data["sources"]:
    count = source["last_record_count"]
    print(
        f"    {source['source']:22} {source['state']:9} "
        f"n={count if count is not None else '-'}"
    )
print(
    f"  all_healthy={data['all_healthy']}  "
    f"priming={data['priming']}  "
    f"stale_config={len(data['stale_config'])}"
)
