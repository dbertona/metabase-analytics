#!/usr/bin/env bash
# merge-safe.sh — superset-analytics
#
# Via unica y auditada para cerrar una rama y publicar en `main` cuando no se
# usan Pull Requests. Portado del esqueleto git de power-solution-apps, con
# validaciones propias de este repo (JSON workflows / SQL), sin npm lint/build.
#
#   1. Verificar rama (no main/master).
#   2. Working tree limpio.
#   3. Validar JSON de workflows tocados (bloqueante, salvo SKIP_VALIDATE=1).
#   4. Aviso si hay SQL tocado (no bloqueante; aplicar vistas es post-merge).
#   5. git checkout main (o merge delegado al worktree que tiene main)
#   6. git merge <rama> --no-ff
#   7. git push gitea main  (overrides DENTRO del script)
#   8. Borrar la rama mergeada (local + gitea + origin si existe)
#   9. Queda en main
#
# Uso:
#   ./scripts/merge-safe.sh                 # usa rama actual
#   ./scripts/merge-safe.sh fix/mi-rama     # rama explicita
#
# Variables:
#   SKIP_VALIDATE=1  -> omite validacion JSON/SQL (solo docs/reglas triviales)
#   DRY_RUN=1        -> no ejecuta merge ni push; solo valida
#   QUIET=1          -> log de validaciones en <git-common-dir>/merge-safe-last.log
#   KEEP_BRANCH=1    -> no borra la rama tras el merge (excepcion explicita)
#
# Alias de compatibilidad con la regla compartida Apps:
#   SKIP_BUILD=1 / SKIP_CONSIST=1  -> tratados como SKIP_VALIDATE=1 (no-op npm)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { printf "${BLUE}>${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}OK${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}WARN${NC} %s\n" "$*"; }
fail() { printf "${RED}FAIL${NC} %s\n" "$*" >&2; exit 1; }

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT_DIR" ] || fail "No estas en un repositorio git."
cd "$ROOT_DIR"

GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "${ROOT_DIR}/.git")"
case "$GIT_COMMON_DIR" in
  /*) : ;;
  *) GIT_COMMON_DIR="${ROOT_DIR}/${GIT_COMMON_DIR}" ;;
esac
QUIET_LOG="${GIT_COMMON_DIR}/merge-safe-last.log"

# Compat: reglas Apps usan SKIP_BUILD / SKIP_CONSIST
if [ "${SKIP_BUILD:-0}" = "1" ] || [ "${SKIP_CONSIST:-0}" = "1" ]; then
  SKIP_VALIDATE="${SKIP_VALIDATE:-1}"
fi

find_main_worktree() {
  git worktree list --porcelain | awk '
    /^worktree / { wt=$2 }
    /^branch refs\/heads\/main$/ { print wt; exit }
  '
}

merge_push_via_main_worktree() {
  local target_branch="$1"
  local main_wt="$2"

  if ! git -C "$main_wt" diff --quiet || ! git -C "$main_wt" diff --cached --quiet; then
    fail "El worktree de main ($main_wt) tiene cambios sin commitear. Limpialo antes del merge."
  fi

  log "Publicando rama $target_branch en gitea (si falta)..."
  export ALLOW_PUSH=1
  git push -u gitea "$target_branch" 2>/dev/null || git push gitea "$target_branch" || true
  unset ALLOW_PUSH

  log "Merge/push en worktree de main: $main_wt"
  git -C "$main_wt" fetch gitea main "$target_branch" --quiet
  git -C "$main_wt" checkout main
  git -C "$main_wt" pull --ff-only gitea main

  export ALLOW_MAIN_COMMIT=1
  export GIT_DIFF_REVIEWED=1
  git -C "$main_wt" merge "$target_branch" --no-ff -m "Merge $target_branch"
  unset ALLOW_MAIN_COMMIT
  unset GIT_DIFF_REVIEWED

  export ALLOW_PUSH=1
  export ALLOW_MAIN_PUSH=1
  export ALLOW_BYPASS_GUARD=1
  git -C "$main_wt" push gitea main
  unset ALLOW_PUSH
  unset ALLOW_MAIN_PUSH
  unset ALLOW_BYPASS_GUARD
}

# Obligatoria tras merge exitoso: borrar feat/fix/hotfix/chore local + remotes.
# No es "rama ajena": es la rama que este script acaba de fusionar en main.
delete_merged_branch() {
  local target_branch="$1"
  local remote

  case "$target_branch" in
    main|master|"")
      fail "Refusing to delete protected branch: '${target_branch}'"
      ;;
    feat/*|fix/*|hotfix/*|chore/*) ;;
    *)
      warn "Nombre de rama inesperado ($target_branch); no borro automaticamente"
      return 0
      ;;
  esac

  if [ "${KEEP_BRANCH:-0}" = "1" ]; then
    warn "KEEP_BRANCH=1 - se conserva $target_branch (local y remoto)"
    return 0
  fi

  if ! git merge-base --is-ancestor "$target_branch" main 2>/dev/null \
    && ! git merge-base --is-ancestor "$target_branch" gitea/main 2>/dev/null; then
    warn "No borro $target_branch: no esta contenida en main tras el merge"
    return 0
  fi

  log "Borrando rama mergeada: $target_branch (local + remotes)"

  # Si seguimos en la feature (p.ej. worktree), salir a main antes de borrar.
  if [ "$(git branch --show-current 2>/dev/null || true)" = "$target_branch" ]; then
    if ! git checkout main 2>/dev/null; then
      git fetch gitea main --quiet 2>/dev/null || true
      git checkout -B main gitea/main 2>/dev/null || {
        warn "No se pudo salir de $target_branch; remotes se borran, local pendiente"
      }
    fi
  fi

  if git show-ref --verify --quiet "refs/heads/$target_branch"; then
    if [ "$(git branch --show-current 2>/dev/null || true)" = "$target_branch" ]; then
      warn "Checkout sigue en $target_branch; no se borra local (borra a mano tras cambiar de rama)"
    else
      git branch -d "$target_branch" 2>/dev/null \
        || git branch -D "$target_branch" \
        || warn "No se pudo borrar local $target_branch"
    fi
  fi

  export ALLOW_PUSH=1
  for remote in gitea origin; do
    if git remote get-url "$remote" >/dev/null 2>&1; then
      if git ls-remote --exit-code --heads "$remote" "$target_branch" >/dev/null 2>&1; then
        git push "$remote" --delete "$target_branch" \
          && ok "Borrada $remote/$target_branch" \
          || warn "Fallo al borrar $remote/$target_branch"
      else
        log "Sin $remote/$target_branch (ya ausente)"
      fi
    fi
  done
  unset ALLOW_PUSH
}

quiet_run() {
  if [ "${QUIET:-0}" = "1" ]; then
    if ! "$@" >>"$QUIET_LOG" 2>&1; then
      printf "${RED}FAIL${NC} Comando fallo: %s\n" "$*" >&2
      if [ -f "$QUIET_LOG" ]; then
        printf "${YELLOW}--- ultimas 40 lineas de %s ---${NC}\n" "$QUIET_LOG" >&2
        tail -40 "$QUIET_LOG" >&2
      fi
      exit 1
    fi
  else
    "$@"
  fi
}

validate_changed_artifacts() {
  local base_ref changed f
  local json_count=0 sql_count=0

  base_ref="$(git merge-base gitea/main HEAD 2>/dev/null || git merge-base main HEAD 2>/dev/null || true)"
  if [ -z "$base_ref" ]; then
    warn "No se pudo resolver merge-base con main — sin lista de cambios"
    return 0
  fi
  changed="$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || true)"

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in
      src/workflows/*.json)
        json_count=$((json_count + 1))
        log "Validando JSON: $f"
        quiet_run python3 -m json.tool "$f" >/dev/null
        python3 -c "
import json, sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
wf = data[0] if isinstance(data, list) else data
if not isinstance(wf, dict):
    raise SystemExit(path + ': raiz invalida')
nodes = wf.get('nodes')
conns = wf.get('connections')
if not isinstance(nodes, list) or not nodes:
    raise SystemExit(path + ': falta nodes[]')
if not isinstance(conns, dict):
    raise SystemExit(path + ': falta connections')
print(f'  nodes={len(nodes)} connections={len(conns)}')
" "$f"
        ok "JSON OK: $f"
        ;;
      sql/*.sql|sql/*/*.sql)
        sql_count=$((sql_count + 1))
        log "SQL tocado: $f"
        ;;
    esac
  done <<< "$changed"

  if [ "$json_count" -eq 0 ]; then
    ok "Sin workflows JSON tocados"
  fi
  if [ "$sql_count" -gt 0 ]; then
    warn "SQL tocado ($sql_count archivo(s)): aplicar vistas en analytics DB post-merge si afecta runtime"
  fi
}

CURRENT_BRANCH="$(git branch --show-current)"
TARGET_BRANCH="${1:-$CURRENT_BRANCH}"

case "$TARGET_BRANCH" in
  main|master|"")
    fail "Rama de origen invalida: '$TARGET_BRANCH'. Debe ser una rama feat/*, fix/* o hotfix/*."
    ;;
esac

log "Rama a cerrar: $TARGET_BRANCH"

if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
  log "Cambiando a $TARGET_BRANCH..."
  git checkout "$TARGET_BRANCH"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "Hay cambios sin commitear en $TARGET_BRANCH. Commitealos o descartalos antes de cerrar."
fi

# Submodulo docs/shared modificado sin commit en el padre
if git status --porcelain | grep -qE '^[ ]*M[ ]+docs/shared|^M[ ]+docs/shared'; then
  fail "docs/shared (submodulo) tiene cambios. Commitea en el submodulo y actualiza la referencia en la rama."
fi

if [ "${QUIET:-0}" = "1" ]; then
  mkdir -p "$GIT_COMMON_DIR"
  : >"$QUIET_LOG"
  log "QUIET=1 - log en $QUIET_LOG"
fi

if [ "${SKIP_VALIDATE:-0}" = "1" ]; then
  warn "SKIP_VALIDATE=1 - omitiendo validacion JSON/SQL"
else
  log "1/3 - validar artefactos de la rama"
  validate_changed_artifacts
  ok "validacion OK"
fi

log "2/3 - actualizando main desde gitea"
git fetch gitea main --quiet

MAIN_WT="$(find_main_worktree)"

if git checkout main 2>/dev/null; then
  git pull --ff-only gitea main
elif [ -n "$MAIN_WT" ]; then
  warn "main esta checkout en otro worktree ($MAIN_WT) — merge delegado"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    warn "DRY_RUN=1 - no ejecuto merge/push delegado"
    exit 0
  fi
  log "3/3 - merge --no-ff delegado de $TARGET_BRANCH a main"
  merge_push_via_main_worktree "$TARGET_BRANCH" "$MAIN_WT"
  delete_merged_branch "$TARGET_BRANCH"
  ok "Rama $TARGET_BRANCH mergeada a main, publicada y eliminada (via $MAIN_WT)"
  warn "Si este worktree seguia en la feature, actualiza: git pull gitea main"
  exit 0
else
  fail "No se pudo hacer checkout de main y no hay worktree con main. Ejecuta merge-safe desde el checkout principal."
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  warn "DRY_RUN=1 - no ejecuto merge/push"
  git checkout "$TARGET_BRANCH"
  exit 0
fi

log "3/3 - merge --no-ff de $TARGET_BRANCH a main"
export ALLOW_MAIN_COMMIT=1
export GIT_DIFF_REVIEWED=1
git merge "$TARGET_BRANCH" --no-ff -m "Merge $TARGET_BRANCH"
unset ALLOW_MAIN_COMMIT
unset GIT_DIFF_REVIEWED

log "Push a gitea/main (con overrides controlados)..."
export ALLOW_PUSH=1
export ALLOW_MAIN_PUSH=1
export ALLOW_BYPASS_GUARD=1
git push gitea main
unset ALLOW_PUSH
unset ALLOW_MAIN_PUSH
unset ALLOW_BYPASS_GUARD
ok "push completado"

delete_merged_branch "$TARGET_BRANCH"

ok "Rama $TARGET_BRANCH mergeada a main, publicada y eliminada. Rama actual: $(git branch --show-current)"
