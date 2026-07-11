#!/bin/bash
# PostToolUse contract: violations exit 2 with the message on stderr; exit 0 otherwise.
FILE="$1"

LAYER=""
case "$FILE" in
  */views/*|*/routes/*|*/api/*)   LAYER="view" ;;
  */services/*)                    LAYER="service" ;;
  */models/*)                      LAYER="model" ;;
  */repositories/*|*/db/*)         LAYER="repository" ;;
  *)                               exit 0 ;;
esac

case "$LAYER" in
  view)
    # Module-boundary match: `from repositories.x`, `from app.db import y` hit;
    # `from db_config import x` does not.
    if grep -qE "^from[[:space:]]+([[:alnum:]_.]*\.)?(repositories|db)(\.|[[:space:]])" "$FILE" 2>/dev/null; then
      {
        echo "LAYER VIOLATION: View/route cannot import from repository"
        echo "File: $FILE"
      } >&2
      exit 2
    fi
    ;;
esac

exit 0
