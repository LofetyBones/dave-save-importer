#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_file="$(mktemp -t DaveBackupTests).swift"
trap 'rm -f "$test_file" "${test_file%.swift}"' EXIT
python3 - "$test_file" <<'PY'
from pathlib import Path
import sys
source = Path('Sources/main.swift').read_text().split('class DropView:')[0]
Path(sys.argv[1]).write_text(source + Path('Tests/BackupTests.swift').read_text())
PY
xcrun swift "$test_file"
