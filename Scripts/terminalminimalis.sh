#!/bin/zsh
# Terminal minimalista + cyberpunk (pro) para macOS
# Incluye seguridad básica, aliases útiles, prompt limpio y toolkit
# CORREGIDO: evita problemas de permisos/owner si se ejecuta con sudo
#
# Uso:
#   chmod +x instalar_terminal_minimal_cyber.sh
#   ./instalar_terminal_minimal_cyber.sh
#
# Si por accidente lo ejecutas con sudo, el script ahora repara ownership al final.

set -euo pipefail

# Usuario real (aunque lo corran con sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(dscl . -read /Users/"$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -z "${REAL_HOME:-}" ]] && REAL_HOME="$HOME"

ZSHRC="${REAL_HOME}/.zshrc"
BACKUP_DIR="${REAL_HOME}/.terminal_style_backups"
KIT_DIR="${REAL_HOME}/Scripts"
TOOLS_DIR="${KIT_DIR}/tools"
OUT_DIR="${KIT_DIR}/out"
LOGS_DIR="${KIT_DIR}/logs"
TPL_DIR="${KIT_DIR}/templates"

mkdir -p "$BACKUP_DIR" "$KIT_DIR" "$TOOLS_DIR" "$OUT_DIR" "$LOGS_DIR" "$TPL_DIR"

timestamp="$(date +%Y%m%d_%H%M%S)"
if [[ -f "$ZSHRC" ]]; then
  cp "$ZSHRC" "${BACKUP_DIR}/.zshrc.backup_${timestamp}"
  echo "✔ Backup creado: ${BACKUP_DIR}/.zshrc.backup_${timestamp}"
else
  touch "$ZSHRC"
  echo "✔ Se creó ${ZSHRC}"
fi

START_MARK="# >>> SAFIYE_TERMINAL_MINIMAL_CYBER_START >>>"
END_MARK="# <<< SAFIYE_TERMINAL_MINIMAL_CYBER_END <<<"

# Limpiar bloque anterior si existe (idempotente)
tmpfile="$(mktemp)"
awk -v start="$START_MARK" -v end="$END_MARK" '
  $0==start {skip=1; next}
  $0==end {skip=0; next}
  !skip {print}
' "$ZSHRC" > "$tmpfile"
mv "$tmpfile" "$ZSHRC"

# Agregar bloque nuevo
cat >> "$ZSHRC" <<'EOF'

# >>> SAFIYE_TERMINAL_MINIMAL_CYBER_START >>>
# ========= Base segura =========
export LANG=es_CL.UTF-8
export LC_ALL=es_CL.UTF-8
umask 077

# Historial potente y útil
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=20000
export SAVEHIST=20000
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY
setopt HIST_VERIFY
setopt NO_BEEP
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_CLOBBER
setopt RM_STAR_WAIT
setopt CORRECT

[[ -f "$HISTFILE" ]] && chmod 600 "$HISTFILE" 2>/dev/null || true

# ========= Estética minimalista + cyberpunk (sin circo) =========
autoload -Uz colors && colors
setopt PROMPT_SUBST

# Colores en ls (BSD/macOS)
export CLICOLOR=1
export LSCOLORS="GxFxCxDxBxegedabagaced"

# PATH local de herramientas
export PATH="$HOME/Scripts/tools:$PATH"

# Título de ventana: user@host ruta
precmd() {
  print -Pn "\e]0;%n@%m: %~\a"
}

# Git branch sin plugins
git_branch() {
  command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return
  local b
  b="$(command git symbolic-ref --short HEAD 2>/dev/null || command git rev-parse --short HEAD 2>/dev/null)"
  [[ -n "$b" ]] && print -n "%{$fg[magenta]%} ${b}%{$reset_color%}"
}

# Estado del último comando (solo si falló)
exit_status() {
  local ec=$?
  [[ $ec -ne 0 ]] && print -n "%{$fg[red]%}[exit:$ec]%{$reset_color%} "
}

# Hora breve
clock_now() {
  print -n "%{$fg[green]%}%D{%H:%M}%{$reset_color%}"
}

# Prompt principal (2 líneas)
PROMPT='$(exit_status)$(clock_now) %{$fg[cyan]%}%n@%m%{$reset_color%} %{$fg[yellow]%}%~%{$reset_color%} $(git_branch)
%{$fg[blue]%}─%{$fg[magenta]%}▶%{$reset_color%} '

# Continuación de línea
PROMPT2='%{$fg[red]%}…%{$reset_color%} '

# Root visible para evitar accidentes
if [[ "$EUID" -eq 0 ]]; then
  PROMPT='$(exit_status)$(clock_now) %{$fg[red]%}%n@%m%{$reset_color%} %{$fg[yellow]%}%~%{$reset_color%} $(git_branch)
%{$fg[red]%}─#%{$reset_color%} '
fi

# Flechas ↑↓ buscan por prefijo en historial
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search

# ========= Aliases seguros y útiles =========
alias ll='ls -lah'
alias la='ls -la'
alias l='ls -CF'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias zreload='source ~/.zshrc'

# Evitar accidentes
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -i'
alias mkdir='mkdir -pv'

# Directorios de trabajo
alias cdkit='cd ~/Scripts'
alias cdout='cd ~/Scripts/out'
alias cdlog='cd ~/Scripts/logs'
alias cdtpl='cd ~/Scripts/templates'

# macOS / soporte / MDM
alias myip='ipconfig getifaddr en0 || ipconfig getifaddr en1'
alias hw='system_profiler SPHardwareDataType'
alias osver='sw_vers'
alias serial='system_profiler SPHardwareDataType | awk -F": " "/Serial Number/{print \$2}"'
alias chip='system_profiler SPHardwareDataType | awk -F": " "/Chip|Processor Name/{print \$2}"'
alias model='system_profiler SPHardwareDataType | awk -F": " "/Model Name/{print \$2}"'
alias whoadmin='dseditgroup -o read admin'
alias mdmstatus='profiles status -type enrollment'
alias mdmlist='profiles list'
alias mdmconf='profiles show -type configuration'
alias ports='sudo lsof -nP -iTCP -sTCP:LISTEN'
alias dnsinfo='scutil --dns'
alias routes='netstat -rn'
alias psg='ps aux | grep -i'
alias pls='plutil -p'
alias pkgs='pkgutil --pkgs | sort'
alias fv='fdesetup status'
alias csr='csrutil status'
alias spctlst='spctl --status'

# ========= Funciones útiles =========

mdmlogs() {
  log show --last "${1:-30m}" --predicate 'process == "mdmclient"' --style compact
}

mdmstream() {
  log stream --info --predicate 'process == "mdmclient"'
}

installlogs() {
  log show --last "${1:-1h}" --predicate 'eventMessage CONTAINS[c] "install"' --style compact
}

macaudit() {
  local host serialn modeln chipn osv userlogged adbound addomain
  host="$(scutil --get ComputerName 2>/dev/null || hostname)"
  serialn="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2; exit}')"
  modeln="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}')"
  chipn="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip|Processor Name/{print $2; exit}')"
  osv="$(sw_vers -productVersion)"
  userlogged="$(stat -f%Su /dev/console)"
  adbound="NO"
  addomain=""

  if command -v dsconfigad >/dev/null 2>&1 && dsconfigad -show >/dev/null 2>&1; then
    adbound="SI"
    addomain="$(dsconfigad -show 2>/dev/null | awk -F'= ' '/Active Directory Domain/{print $2; exit}')"
  fi

  cat <<JSON
{
  "hostname":"${host}",
  "serial":"${serialn}",
  "model":"${modeln}",
  "chip":"${chipn}",
  "macos":"${osv}",
  "logged_user":"${userlogged}",
  "ad_bound":"${adbound}",
  "ad_domain":"${addomain}"
}
JSON
}

macusers() {
  dscl . list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $1}' | while read -r u; do
    if dscl . -read "/Users/$u" AuthenticationAuthority 2>/dev/null | grep -qi "LocalCachedUser"; then
      echo "$u,MOBILE"
    else
      echo "$u,LOCAL"
    fi
  done
}

# Triage rápido (opcionalmente recibe ID de ticket) y guarda evidencia con timestamp
triage() {
  local ticket ts outdir safe_ticket
  ticket="${1:-}"
  ts="$(date +%Y%m%d_%H%M%S)"

  if [[ -n "$ticket" ]]; then
    safe_ticket="$(echo "$ticket" | tr -cd '[:alnum:]_.-')"
    outdir="$HOME/Scripts/out/${safe_ticket}_${ts}"
  else
    outdir="$HOME/Scripts/out/triage_${ts}"
  fi

  mkdir -p "$outdir"

  {
    echo "===== MACAUDIT ====="
    macaudit
    echo
    echo "===== USERS ====="
    macusers
    echo
    echo "===== MDM STATUS ====="
    profiles status -type enrollment 2>&1 || true
    echo
    echo "===== SW_VERS ====="
    sw_vers
    echo
    echo "===== HARDWARE ====="
    system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Model Name|Model Identifier|Chip|Processor Name|Serial Number'
  } | tee "$outdir/resumen.txt"

  log show --last 20m --predicate 'process == "mdmclient"' --style compact > "$outdir/mdmclient.log" 2>/dev/null || true

  echo "✔ Triage guardado en: $outdir"
}

# Crear plantillas rápidas
mkbash() {
  local name="${1:-script_nuevo}"
  local target="$HOME/Scripts/${name}.sh"
  [[ -e "$target" ]] && { echo "Ya existe: $target"; return 1; }

  cat > "$target" <<'BASH'
#!/bin/bash
set -euo pipefail
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

main() {
  log "Inicio"
  # TODO
  log "Fin"
}
main "$@"
BASH
  chmod +x "$target"
  echo "✔ Creado: $target"
}

mkzsh() {
  local name="${1:-script_nuevo_zsh}"
  local target="$HOME/Scripts/${name}.zsh"
  [[ -e "$target" ]] && { echo "Ya existe: $target"; return 1; }

  cat > "$target" <<'ZSH'
#!/bin/zsh
set -euo pipefail
log(){ print "[$(date '+%F %T')] $*"; }

main() {
  log "Inicio"
  # TODO
  log "Fin"
}
main "$@"
ZSH
  chmod +x "$target"
  echo "✔ Creado: $target"
}

mkpy() {
  local name="${1:-script_python}"
  local target="$HOME/Scripts/${name}.py"
  [[ -e "$target" ]] && { echo "Ya existe: $target"; return 1; }

  cat > "$target" <<'PY'
#!/usr/bin/env python3
from datetime import datetime

def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

def main() -> None:
    log("Inicio")
    # TODO
    log("Fin")

if __name__ == "__main__":
    main()
PY
  chmod +x "$target"
  echo "✔ Creado: $target"
}

# Buscar texto rápido
ff() {
  local pattern="${1:-}"
  local path="${2:-.}"
  [[ -z "$pattern" ]] && { echo "Uso: ff <patron> [ruta]"; return 1; }
  grep -Rni --exclude-dir=.git -- "$pattern" "$path"
}

# Ver permisos extendidos
perms() {
  ls -le@ "$@"
}

# Modo foco (limpia y ajusta ventana si el terminal lo soporta)
alias foco='printf "\e[8;38;140t" 2>/dev/null || true; clear'

recordatorios_terminal() {
  cat <<'TXT'
REGLAS DE ORO:
1) Primero observar, luego cambiar.
2) Guarda evidencia (logs/salidas) con timestamp.
3) Si no puedes explicarlo, no lo despliegues.
4) Scripts idempotentes > scripts heroicos.
5) Prueba en laboratorio antes de MDM masivo.
TXT
}
# <<< SAFIYE_TERMINAL_MINIMAL_CYBER_END <<<
EOF

# Toolkit mínimo
cat > "${TOOLS_DIR}/mac_audit_quick.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
SERIAL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2; exit}')"
MODEL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}')"
CHIP="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip|Processor Name/{print $2; exit}')"
OS="$(sw_vers -productVersion)"
USERLOGGED="$(stat -f%Su /dev/console)"

cat <<JSON
{"hostname":"${HOST}","serial":"${SERIAL}","model":"${MODEL}","chip":"${CHIP}","macos":"${OS}","logged_user":"${USERLOGGED}"}
JSON
EOF
chmod +x "${TOOLS_DIR}/mac_audit_quick.sh"

cat > "${TPL_DIR}/template_bash.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
main(){ log "Inicio"; # TODO ; log "Fin"; }
main "$@"
EOF
chmod +x "${TPL_DIR}/template_bash.sh"

# ===== Reparación de owner/permisos (clave) =====
# Si se ejecutó con sudo, deja todo perteneciendo al usuario real.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  chown "${REAL_USER}":staff "$ZSHRC" 2>/dev/null || true
  chown -R "${REAL_USER}":staff "$KIT_DIR" "$BACKUP_DIR" 2>/dev/null || true
fi

# Permisos sanos (archivo personal y carpetas privadas)
chmod 600 "$ZSHRC" 2>/dev/null || true
chmod 700 "$KIT_DIR" "$TOOLS_DIR" "$OUT_DIR" "$LOGS_DIR" "$TPL_DIR" 2>/dev/null || true

echo ""
echo "✅ Listo. Terminal minimalista/cyberpunk instalada."
echo "➡️  Ejecuta: source ~/.zshrc"
echo "➡️  Prueba: triage"
echo "➡️  Prueba: triage INC123456"
echo "➡️  Prueba: macaudit"
echo "➡️  Prueba: mdmlogs 15m"
echo "➡️  Prueba: mkbash prueba_script"