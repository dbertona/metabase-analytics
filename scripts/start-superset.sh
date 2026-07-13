#!/usr/bin/env bash
# Alias de compatibilidad — usar scripts/start.sh
exec "$(dirname "$0")/start.sh" "$@"
