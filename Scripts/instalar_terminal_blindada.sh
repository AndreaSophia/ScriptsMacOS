#!/bin/zsh
# Terminal Blindada + Toolkit de scripting para macOS
# Autor: ChatGPT (adaptado para Safiye)
# Uso: chmod +x instalar_terminal_blindada.sh && ./instalar_terminal_blindada.sh

set -euo pipefail

echo "==> Iniciando configuración de terminal segura y toolkit macOS..."

ZSHRC="${HOME}/.zshrc"
BACKUP_DIR="${HOME}/.terminal_blindada_backups"
KIT_DIR="${HOME}/Scripts"
TEMPLATES_DIR="${KIT_DIR}/templates"
TOOLS_DIR="${KIT_DIR}/tools"
LOGS_DIR="${KIT_DIR}/logs"
OUT_DIR="${KIT_DIR}/out"
CHEATSHEET="${KIT_DIR}/CHEATSHEET_MAC.md"

mkdir -p "$BACKUP_DIR" "$TEMPLATES_DIR" "$TOOLS_DIR" "$LOGS_DIR" "$OUT_DIR"

# 1) Backup de .zshrc si existe
timestamp="$(date +%Y%m%d_%H%M%S)"
if [[ -f "$ZSHRC" ]]; then
  cp "$ZSHRC" "${BACKUP_DIR}/.zshrc.backup_${timestamp}"
  echo "✔ Backup de .zshrc creado en ${BACKUP_DIR}"
else
  touch "$ZSHRC"
  echo "✔ Se creó .zshrc nuevo"
fi

# 2) Bloque administrado para .zshrc (idempotente)
START_MARK="# >>> TERMINAL_BLINDADA_SAFIYE_START >>>"
END_MARK="# <<< TERMINAL_BLINDADA_SAFIYE_END <<<"

# Elimina bloque previo si existe
tmpfile="$(mktemp)"
awk -v start="$START_MARK" -v end="$END_MARK" '
  $0==start {skip=1; next}
  $0==end {skip=0; next}
  !skip {print}
' "$ZSHRC" > "$tmpfile"
mv "$tmpfile" "$ZSHRC"

cat >> "$ZSHRC" <<'EOF'

# >>> TERMINAL_BLINDADA_SAFIYE_START >>>
# Seguridad y ergonomía básica para zsh
export LANG=es_CL.UTF-8
export LC_ALL=es_CL.UTF-8
umask 077

# Historial robusto y útil
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=20000
export SAVEHIST=20000
setopt APPEND_HISTORY           # agrega en vez de sobreescribir
setopt INC_APPEND_HISTORY       # escribe en tiempo real
setopt SHARE_HISTORY            # comparte historial entre sesiones
setopt HIST_IGNORE_DUPS         # ignora duplicados consecutivos
setopt HIST_IGNORE_ALL_DUPS     # borra duplicados viejos
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY         # timestamps
setopt HIST_VERIFY              # expande ! pero deja revisar antes
setopt NO_BEEP
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS

# “Guardrails” (barandas para no pegarse)
setopt NO_CLOBBER               # evita > accidental sobre archivos
setopt RM_STAR_WAIT             # frena rm * accidental
setopt CORRECT                  # corrige typo básicos de comandos

# Permisos del historial (si ya existe)
[[ -f "$HISTFILE" ]] && chmod 600 "$HISTFILE"

# Prompt simple y útil (sin circo, con info)
autoload -Uz colors && colors
setopt PROMPT_SUBST
PROMPT='%{$fg[cyan]%}%n@%m%{$reset_color%}:%{$fg[yellow]%}%~%{$reset_color%} %(?.%{$fg[green]%}✓.%{$fg[red]%}✗)%{$reset_color%} '

# Rutas de trabajo
export PATH="$HOME/Scripts/tools:$PATH"

# Alias seguros y de uso diario
alias ll='ls -lah'
alias la='ls -la'
alias l='ls -CF'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'

# Evita accidentes
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -i'
alias mkdir='mkdir -pv'

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

# Logs útiles (mdm / install / unified logging)
mdmlogs() {
  log show --last "${1:-30m}" --predicate 'process == "mdmclient"' --style compact
}

mdmstream() {
  log stream --info --predicate 'process == "mdmclient"'
}

installlogs() {
  log show --last "${1:-1h}" --predicate 'eventMessage CONTAINS[c] "install"' --style compact
}

# Auditoría rápida del Mac (salida JSON simple)
macaudit() {
  local host serial model chip osver userlogged adbound addomain
  host="$(scutil --get ComputerName 2>/dev/null || hostname)"
  serial="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F": " '/Serial Number/{print $2; exit}')"
  model="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F": " '/Model Name/{print $2; exit}')"
  chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F": " '/Chip|Processor Name/{print $2; exit}')"
  osver="$(sw_vers -productVersion)"
  userlogged="$(stat -f%Su /dev/console)"
  adbound="NO"
  addomain=""
  if dsconfigad -show >/dev/null 2>&1; then
    adbound="SI"
    addomain="$(dsconfigad -show 2>/dev/null | awk -F'= ' '/Active Directory Domain/{print $2; exit}')"
  fi

  cat <<JSON
{
  "hostname": "${host}",
  "serial": "${serial}",
  "model": "${model}",
  "chip": "${chip}",
  "macos": "${osver}",
  "logged_user": "${userlogged}",
  "ad_bound": "${adbound}",
  "ad_domain": "${addomain}"
}
JSON
}

# Usuarios locales vs “móviles” (aproximación útil para soporte)
macusers() {
  dscl . list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $1}' | while read -r u; do
    if dscl . -read "/Users/$u" AuthenticationAuthority 2>/dev/null | grep -qi "LocalCachedUser"; then
      echo "$u,MOBILE"
    else
      echo "$u,LOCAL"
    fi
  done
}

# Crea script plantilla rápidamente: mkbash nombre_script
mkbash() {
  local name="${1:-script_nuevo}"
  local target="$HOME/Scripts/${name}.sh"
  if [[ -e "$target" ]]; then
    echo "Ya existe: $target"
    return 1
  fi
  cat > "$target" <<'BASH'
#!/bin/bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

main() {
  log "Inicio"
  # TODO: tu lógica aquí
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
  if [[ -e "$target" ]]; then
    echo "Ya existe: $target"
    return 1
  fi
  cat > "$target" <<'ZSH'
#!/bin/zsh
set -euo pipefail

log() { print "[$(date '+%F %T')] $*"; }

main() {
  log "Inicio"
  # TODO: tu lógica aquí
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
  if [[ -e "$target" ]]; then
    echo "Ya existe: $target"
    return 1
  fi
  cat > "$target" <<'PY'
#!/usr/bin/env python3
from datetime import datetime

def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

def main() -> None:
    log("Inicio")
    # TODO: tu lógica aquí
    log("Fin")

if __name__ == "__main__":
    main()
PY
  chmod +x "$target"
  echo "✔ Creado: $target"
}

# Utilidad para buscar texto en plists y logs
ff() {
  # uso: ff patron [ruta]
  local pattern="${1:-}"
  local path="${2:-.}"
  if [[ -z "$pattern" ]]; then
    echo "Uso: ff <patron> [ruta]"
    return 1
  fi
  grep -Rni --exclude-dir=.git -- "$pattern" "$path"
}

# Ver permisos y dueño rápido
perms() {
  ls -le@ "$@"
}

# Refrescar shell rápido
alias zreload='source ~/.zshrc'

# Atajos de directorios
alias cdkit='cd ~/Scripts'
alias cdlog='cd ~/Scripts/logs'
alias cdout='cd ~/Scripts/out'
alias cdtpl='cd ~/Scripts/templates'

# Recordatorios rápidos (truco mental)
recordatorios_terminal() {
  cat <<'TXT'
REGLAS DE ORO (no romper prod por deporte):
1) Primero observar, luego cambiar.
2) Siempre guardar evidencia (log, salida, timestamp).
3) Si no puedes explicar el cambio, no lo ejecutes.
4) Scripts idempotentes > scripts heroicos.
5) Probar en un Mac de laboratorio antes de MDM masivo.
TXT
}
# <<< TERMINAL_BLINDADA_SAFIYE_END <<<
EOF

echo "✔ Bloque seguro agregado a .zshrc"

# 3) Plantillas base en ~/Scripts/templates
cat > "${TEMPLATES_DIR}/template_bash.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

cleanup() {
  # limpieza opcional
  :
}
trap cleanup EXIT

main() {
  log "Inicio"
  # TODO
  log "Fin"
}

main "$@"
EOF
chmod +x "${TEMPLATES_DIR}/template_bash.sh"

cat > "${TEMPLATES_DIR}/template_zsh.zsh" <<'EOF'
#!/bin/zsh
set -euo pipefail

log() { print "[$(date '+%F %T')] $*"; }

main() {
  log "Inicio"
  # TODO
  log "Fin"
}

main "$@"
EOF
chmod +x "${TEMPLATES_DIR}/template_zsh.zsh"

cat > "${TEMPLATES_DIR}/template_python.py" <<'EOF'
#!/usr/bin/env python3
from datetime import datetime
import json

def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

def main() -> None:
    log("Inicio")
    payload = {"ok": True}
    print(json.dumps(payload, ensure_ascii=False))
    log("Fin")

if __name__ == "__main__":
    main()
EOF
chmod +x "${TEMPLATES_DIR}/template_python.py"

# 4) Cheatsheet útil y realista para macOS/MDM
cat > "$CHEATSHEET" <<'EOF'
# CHEATSHEET MAC - Terminal de trabajo (Safiye)

## Identidad del equipo
- `serial`
- `model`
- `chip`
- `osver`
- `macaudit`

## Usuarios
- `whoadmin`  -> miembros del grupo admin
- `macusers`  -> usuarios local vs mobile (aprox)
- `stat -f%Su /dev/console` -> usuario logueado

## MDM / perfiles
- `mdmstatus`
- `mdmlist`
- `mdmconf`
- `mdmlogs 1h`
- `mdmstream`

## Red
- `ifconfig`
- `dnsinfo`
- `routes`
- `myip`
- `ports`

## Seguridad
- `fv`
- `csr`
- `spctlst`

## Paquetes / plist
- `pkgs`
- `pkgutil --pkg-info <id>`
- `pls /ruta/archivo.plist`

## Logs (Unified Logging)
- `log show --last 30m --style compact`
- `installlogs 2h`

## Plantillas rápidas
- `mkbash nombre_script`
- `mkzsh nombre_script`
- `mkpy nombre_script`

## Regla práctica
Antes de tocar algo:
1. Saca evidencia
2. Toma baseline
3. Prueba
4. Recién automatiza
EOF

# 5) Script de auditoría rápida listo para usar
cat > "${TOOLS_DIR}/mac_audit_quick.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
SERIAL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2; exit}')"
MODEL="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/{print $2; exit}')"
CHIP="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip|Processor Name/{print $2; exit}')"
OS="$(sw_vers -productVersion)"
USERLOGGED="$(stat -f%Su /dev/console)"

AD_BOUND="NO"
AD_DOMAIN=""
if dsconfigad -show >/dev/null 2>&1; then
  AD_BOUND="SI"
  AD_DOMAIN="$(dsconfigad -show 2>/dev/null | awk -F'= ' '/Active Directory Domain/{print $2; exit}')"
fi

cat <<JSON
{
  "hostname":"${HOST}",
  "serial":"${SERIAL}",
  "model":"${MODEL}",
  "chip":"${CHIP}",
  "macos":"${OS}",
  "logged_user":"${USERLOGGED}",
  "ad_bound":"${AD_BOUND}",
  "ad_domain":"${AD_DOMAIN}"
}
JSON
EOF
chmod +x "${TOOLS_DIR}/mac_audit_quick.sh"

# 6) Permisos sanos en carpeta Scripts
chmod 700 "$KIT_DIR" "$TOOLS_DIR" "$LOGS_DIR" "$OUT_DIR" "$TEMPLATES_DIR"
chmod 600 "$CHEATSHEET"

echo "✔ Toolkit creado en: $KIT_DIR"
echo "✔ Cheatsheet: $CHEATSHEET"
echo "✔ Plantillas: $TEMPLATES_DIR"
echo "✔ Herramientas: $TOOLS_DIR"

echo
echo "==> Listo."
echo "Abre una nueva terminal o ejecuta: source ~/.zshrc"
echo "Prueba estos comandos:"
echo "  macaudit"
echo "  macusers"
echo "  mdmstatus"
echo "  mdmlogs 15m"
echo "  mkbash prueba_script"
echo "  recordatorios_terminal"