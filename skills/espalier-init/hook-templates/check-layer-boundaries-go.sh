#!/bin/bash
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
      echo "LAYER VIOLATION: Handler cannot import repository directly"
      echo "File: $FILE"
      exit 1
    fi
    ;;
esac

exit 0
