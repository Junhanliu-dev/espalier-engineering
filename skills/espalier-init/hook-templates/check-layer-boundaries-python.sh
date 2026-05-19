#!/bin/bash
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
    if grep -qE "^from .*(repositories|db)" "$FILE" 2>/dev/null; then
      echo "LAYER VIOLATION: View/route cannot import from repository"
      echo "File: $FILE"
      exit 1
    fi
    ;;
esac

exit 0
