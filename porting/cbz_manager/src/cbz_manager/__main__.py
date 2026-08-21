"""Allow running as `python -m cbz_manager`."""

from __future__ import annotations

import sys

from cbz_manager.cli import main

sys.exit(main())
