#!/bin/sh
set -e

if [ "$SEED_ON_START" = "true" ]; then
  echo "SEED_ON_START=true → running idempotent seed..."
  python scripts/seed_demo_data.py || echo "seed step failed (continuing to start server)"
fi

exec uvicorn app.main:app --host 0.0.0.0 --port 8000
