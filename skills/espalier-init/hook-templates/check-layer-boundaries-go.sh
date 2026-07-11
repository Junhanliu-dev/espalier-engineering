#!/bin/bash
# PostToolUse contract: violations exit 2 with the message on stderr; exit 0 otherwise.
FILE="$1"

LAYER=""
case "$FILE" in
  */handler/*|*/cmd/*)       LAYER="handler" ;;
  */service/*)               LAYER="service" ;;
  */repository/*|*/store/*)  LAYER="repository" ;;
  */client/*)                LAYER="client" ;;
  *)                         exit 0 ;;
esac

case "$LAYER" in
  handler)
    if grep -q '".*repository"' "$FILE" 2>/dev/null || grep -q '".*store"' "$FILE" 2>/dev/null; then
      {
        echo "LAYER VIOLATION: Handler cannot import repository directly"
        echo "File: $FILE"
      } >&2
      exit 2
    fi
    ;;
esac

exit 0
