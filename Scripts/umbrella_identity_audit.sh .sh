#!/bin/bash
# Umbrella + Identity + MDM diagnostic for macOS (Intune / local, mobile, AD-bound)
# Creates a detailed log on the current user's Desktop.
# Run:  chmod +x umbrella_identity_audit.sh && ./umbrella_identity_audit.sh
# Tip:  run with sudo for deeper visibility: sudo ./umbrella_identity_audit.sh

set -u

ts() { date "+%Y-%m-%d %H:%M:%S%z"; }

# Resolve the "real" console user (avoid root when run with sudo)
CONSOLE_USER="$(/usr/sbin/scutil <<<"show State:/Users/ConsoleUser" | awk '/Name :/ {print $3}' | head -n1)"
if [[ -z "${CONSOLE_USER}" || "${CONSOLE_USER}" == "loginwindow" ]]; then
  CONSOLE_USER="$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)"
fi
HOME_DIR="$(/usr/bin/dscl . -read /Users/"$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' | head -n1)"
if [[ -z "${HOME_DIR}" ]]; then HOME_DIR="/Users/${CONSOLE_USER}"; fi

DESKTOP="${HOME_DIR}/Desktop"
LOG="${DESKTOP}/Umbrella_Identity_Audit_${CONSOLE_USER}_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

echo "======================================================================"
echo "Umbrella / Identity / MDM Audit"
echo "Time:          $(ts)"
echo "Hostname:      $(hostname)"
echo "Console user:  ${CONSOLE_USER}"
echo "Home dir:      ${HOME_DIR}"
echo "Log file:      ${LOG}"
echo "======================================================================"
echo

run_cmd() {
  local title="$1"; shift
  local cmd="$*"
  echo "------------------------------------------------------------------"
  echo "[$(ts)] ${title}"
  echo "CMD: ${cmd}"
  echo "------------------------------------------------------------------"
  # shellcheck disable=SC2086
  eval ${cmd} 2>&1 || echo "[WARN] Command failed (exit=$?)"
  echo
}

section() {
  echo
  echo "######################################################################"
  echo "# $1"
  echo "######################################################################"
  echo
}

# ------------------------------------------------------------
# 0) Basic system facts
# ------------------------------------------------------------
section "0) System & OS"
run_cmd "macOS version" "/usr/bin/sw_vers"
run_cmd "Hardware overview" "/usr/sbin/system_profiler SPHardwareDataType | sed -n '1,80p'"
run_cmd "Network - active interfaces" "/usr/sbin/networksetup -listallhardwareports"
run_cmd "Network - IP addresses" "/sbin/ifconfig | awk '/^[a-z]/{iface=\$1} /inet /{print iface,\$2}'"
run_cmd "DNS resolvers" "/usr/sbin/scutil --dns | sed -n '1,200p'"

# ------------------------------------------------------------
# 1) Local user + mobile account (AD/Directory mobile) checks
# ------------------------------------------------------------
section "1) User identity on Mac (local vs mobile vs directory-backed)"
run_cmd "User record summary (dscl)" "/usr/bin/dscl . -read /Users/${CONSOLE_USER} UniqueID PrimaryGroupID UserShell NFSHomeDirectory 2>/dev/null"
run_cmd "AuthenticationAuthority (detect Mobile account hints)" "/usr/bin/dscl . -read /Users/${CONSOLE_USER} AuthenticationAuthority 2>/dev/null"
run_cmd "dseditgroup - check admin membership" "/usr/sbin/dseditgroup -o checkmember -m ${CONSOLE_USER} admin 2>/dev/null || true"

# Heuristic: mobile accounts often show "LocalCachedUser" or "Active Directory" in AuthenticationAuthority.
echo "[$(ts)] Mobile-account heuristic:"
AA="$(/usr/bin/dscl . -read /Users/${CONSOLE_USER} AuthenticationAuthority 2>/dev/null | tr -d '\n' || true)"
if echo "$AA" | /usr/bin/grep -Eqi "LocalCachedUser|Active Directory|Kerberosv5|NetLogon"; then
  echo "  Likely: MOBILE / directory-backed (cached) account (found AD/Kerberos hints)."
else
  echo "  Likely: LOCAL account (no AD/Kerberos hints detected)."
fi
echo

# ------------------------------------------------------------
# 2) Active Directory binding status (dsconfigad)
# ------------------------------------------------------------
section "2) Active Directory binding (AD-bound or not)"
if /usr/bin/command -v /usr/sbin/dsconfigad >/dev/null 2>&1; then
  run_cmd "dsconfigad -show" "/usr/sbin/dsconfigad -show 2>/dev/null || true"
else
  echo "[INFO] dsconfigad not present (unexpected on macOS)."
fi

# Check Directory Services search paths (useful when bound)
run_cmd "DirectoryService search paths" "/usr/bin/dscl /Search -read . CSPSearchPath 2>/dev/null || true"
run_cmd "DirectoryService contacts search paths" "/usr/bin/dscl /Search -read . CSPSearchPath 2>/dev/null || true"

# Domain join hints in system logs (last 7 days, light)
run_cmd "Log hints: DirectoryService / opendirectoryd / dsconfigad (last 7d)" \
"/usr/bin/log show --style syslog --last 7d --predicate '(process == \"opendirectoryd\" OR process == \"DirectoryService\" OR process == \"dsconfigad\")' | tail -n 200"

# ------------------------------------------------------------
# 3) Intune / MDM enrollment evidence
# ------------------------------------------------------------
section "3) MDM / Intune enrollment evidence"

# Profiles overview
run_cmd "profiles status" "/usr/bin/profiles status -type enrollment 2>/dev/null || true"
run_cmd "profiles list (summary)" "/usr/bin/profiles list 2>/dev/null | sed -n '1,220p'"

# Check if an MDM profile exists + provider info
run_cmd "profiles show type enrollment" "/usr/bin/profiles show -type enrollment 2>/dev/null || true"

# Intune Company Portal presence
run_cmd "Company Portal app presence" \
"/bin/ls -la '/Applications/Company Portal.app' 2>/dev/null || /usr/bin/mdfind 'kMDItemCFBundleIdentifier == \"com.microsoft.CompanyPortal\"' | head -n 20"

# Microsoft Intune / MDM daemon hints
run_cmd "LaunchDaemons/Agents - Microsoft/Intune hints" \
"/bin/ls -la /Library/LaunchDaemons 2>/dev/null | /usr/bin/grep -Ei 'microsoft|intune|companyportal|mdm' || true"
run_cmd "Running processes - Microsoft/Intune hints" \
"/bin/ps aux | /usr/bin/grep -Ei 'Company Portal|Intune|Microsoft|mdmagent|portal' | /usr/bin/grep -v grep || true"

# ------------------------------------------------------------
# 4) Umbrella / AnyConnect / OpenDNS components
# ------------------------------------------------------------
section "4) Umbrella / AnyConnect / OpenDNS: installed components"

echo "[$(ts)] Checking common install locations..."
run_cmd "Applications - Umbrella/AnyConnect/OpenDNS candidates" \
"/bin/ls -la /Applications 2>/dev/null | /usr/bin/grep -Ei 'umbrella|opendns|anyconnect|secure client|cisco' || true"

# Cisco Secure Client (AnyConnect) typical paths
run_cmd "Cisco Secure Client folders" \
"/bin/ls -la '/opt/cisco' 2>/dev/null; /bin/ls -la '/opt/cisco/secureclient' 2>/dev/null || true"

# Old Umbrella roaming client locations (varies by version)
run_cmd "OpenDNS/Umbrella roaming client folders" \
"/bin/ls -la '/Library/Application Support' 2>/dev/null | /usr/bin/grep -Ei 'OpenDNS|Umbrella' || true"

# Binaries that often exist
run_cmd "Binary hunt: umbrella/opendns/anyconnect executables (quick)" \
"/usr/bin/which -a scutil 2>/dev/null; /usr/bin/which -a python3 2>/dev/null; \
/usr/bin/find /usr/local/bin /opt -maxdepth 4 -type f 2>/dev/null | /usr/bin/grep -Ei 'umbrella|opendns|anyconnect|secureclient' | head -n 80 || true"

# Processes
run_cmd "Running processes - Umbrella/AnyConnect/OpenDNS" \
"/bin/ps aux | /usr/bin/grep -Ei 'umbrella|opendns|anyconnect|secure client|cisco' | /usr/bin/grep -v grep || true"

# System Extensions / Network Extensions (Umbrella often uses these)
section "5) Network/System extensions (common for security agents)"
run_cmd "systemextensionsctl list" "/usr/sbin/systemextensionsctl list 2>/dev/null || true"
run_cmd "NetworkExtensions (sysext) from logs (last 2d, tail)" \
"/usr/bin/log show --style syslog --last 2d --predicate '(subsystem CONTAINS \"com.apple.networkextension\" OR message CONTAINS[c] \"umbrella\" OR message CONTAINS[c] \"opendns\" OR message CONTAINS[c] \"anyconnect\" OR message CONTAINS[c] \"secure client\")' | tail -n 250"

# DNS proxy / content filter can be visible in NE config (limited)
run_cmd "Network services (proxy-ish quick view)" "/usr/sbin/scutil --nwi 2>/dev/null || true"

# ------------------------------------------------------------
# 6) Umbrella logs collection (best-effort)
# ------------------------------------------------------------
section "6) Umbrella/AnyConnect logs: locate + tail (best-effort)"

echo "[$(ts)] Looking for common log files..."
CANDIDATES=(
  "/Library/Application Support/OpenDNS Roaming Client/logs"
  "/Library/Logs/OpenDNS Roaming Client"
  "/Library/Logs/Umbrella"
  "/Library/Logs/Cisco"
  "/opt/cisco/secureclient/logs"
  "/opt/cisco/anyconnect/logs"
  "/var/log"
)

for p in "${CANDIDATES[@]}"; do
  if [[ -d "$p" ]]; then
    echo "[FOUND] Directory: $p"
    /bin/ls -la "$p" | head -n 60
    echo
  fi
done

# Tail a few largest/most recent relevant logs
echo "[$(ts)] Tail recent relevant log files (umbrella/opendns/cisco keywords):"
run_cmd "Recent log files (search) - last modified" \
"/usr/bin/find /Library/Logs /var/log '/Library/Application Support' -maxdepth 4 -type f 2>/dev/null | \
/usr/bin/grep -Ei 'umbrella|opendns|cisco|anyconnect|secureclient' | \
/usr/bin/xargs -I{} /bin/ls -lt {} 2>/dev/null | head -n 40 || true"

# Extract identity-related lines from unified logs
section "7) Unified logs: identity signals (last 24h)"
run_cmd "Umbrella/OpenDNS/AnyConnect mentions (last 24h, tail)" \
"/usr/bin/log show --style syslog --last 24h --predicate '(message CONTAINS[c] \"umbrella\" OR message CONTAINS[c] \"opendns\" OR message CONTAINS[c] \"anyconnect\" OR message CONTAINS[c] \"secure client\")' | tail -n 400"

run_cmd "SSO/Auth hints (last 24h, tail)" \
"/usr/bin/log show --style syslog --last 24h --predicate '(message CONTAINS[c] \"SAML\" OR message CONTAINS[c] \"OIDC\" OR message CONTAINS[c] \"token\" OR message CONTAINS[c] \"authentication\" OR message CONTAINS[c] \"Kerberos\" OR message CONTAINS[c] \"NTLM\")' | tail -n 250"

# ------------------------------------------------------------
# 8) Snapshot of key identity attributes: UPN/mail guesses
# ------------------------------------------------------------
section "8) Identity summary (best-effort guess of UPN/mail from local context)"

echo "[$(ts)] Console user: ${CONSOLE_USER}"
echo "[$(ts)] AD binding domain (if any):"
if /usr/bin/command -v /usr/sbin/dsconfigad >/dev/null 2>&1; then
  /usr/sbin/dsconfigad -show 2>/dev/null | /usr/bin/grep -E "Active Directory Domain|Computer Account|Forest" || true
fi
echo

# If bound, try reading AD attributes for the user (may fail depending on perms)
echo "[$(ts)] Attempt: read AD node user record (may fail if not accessible)..."
AD_NODE="$(/usr/bin/dscl /Search -list / 2>/dev/null | /usr/bin/grep -E '^Active Directory' | head -n1 || true)"
if [[ -n "$AD_NODE" ]]; then
  echo "  AD node detected: $AD_NODE"
  run_cmd "dscl read user record from AD node (limited)" "/usr/bin/dscl \"/$AD_NODE/All Domains\" -read /Users/${CONSOLE_USER} 2>/dev/null || true"
else
  echo "  No AD node detected in dscl /Search."
fi
echo

# ------------------------------------------------------------
# 9) Conclusions hints (printed, not magic)
# ------------------------------------------------------------
section "9) Quick interpretation hints (non-authoritative)"

echo "If Umbrella shows user ONLY when AD-bound:"
echo "  -> Identity source is likely AD/binding/AD Connector, not Entra/SSO."
echo
echo "If you want user identity on local-account Macs:"
echo "  -> Umbrella must use cloud identity (IdP/SSO) or device identity consistently."
echo
echo "If logs show UPN/mail mismatches:"
echo "  -> Fix the *contract*: claim from IdP == identifier WS1/Umbrella expects."
echo
echo "======================================================================"
echo "DONE. Log saved to: ${LOG}"
echo "======================================================================"
echo
