#!/bin/bash
# AUTO-GENERATED: Published to GitHub Pages by CI on each tagged release.
# Do not edit the published copy — edit install.sh in the atlassian-mcp-server repo instead.
#
# Installs the latest Atlassian MCP Server extension (.mcpb) into Claude Desktop and saves an API token for
# each Atlassian site.
#   curl -fsSL https://wpp-jamie-mills.github.io/atlassian-mcp-server-site/install.sh | bash
#   curl -fsSL <same url> | bash -s -- --site yourcompany.atlassian.net
# For an AI agent (no terminal: it never quits or restarts an app, and doesn't wait for the install dialog):
#   curl -fsSL <same url> | ATLASSIAN_INSTALL_TTY=/dev/null bash -s -- --no-wait
#   (it never opens the token prompt, which waits for a person: tokens are saved later by atlassian_set_token,
#   or by running the installer in a terminal)
#
# Environment overrides (mainly for tests):
#   ATLASSIAN_MCP_HOME          data folder (--dir wins)
#   ATLASSIAN_INSTALL_SITES     sites to set up, separated by spaces or commas (--site wins; default
#                               DEFAULT_SITES below)
#   ATLASSIAN_INSTALL_BASE      base URL for the download files (default: the GitHub Pages site)
#   ATLASSIAN_CLAUDE_APP        path to Claude.app (default /Applications/Claude.app)
#   ATLASSIAN_INSTALL_NO_OPEN   1 = don't open the .mcpb, web pages or notifications, and never quit or reopen
#                               an app; just say what would happen
#   ATLASSIAN_INSTALL_TTY       where prompts are read from (default /dev/tty)
#   ATLASSIAN_INSTALL_WAIT_SECS how long to wait for Claude to list the new version (default 600; 0 with
#                               ATLASSIAN_INSTALL_NO_OPEN or --no-wait)
#   ATLASSIAN_KEYCHAIN_SERVICE  Keychain service for the tokens (default atlassian-mcp-server; letters, digits,
#                               . _ - only). Each site's token is an item with the site as its account.
#   ATLASSIAN_INSTALL_SKIP_TOKEN  1 = skip the token step (automation and tests)
#   ATLASSIAN_INSTALL_NOTIFY    1 = show the final notification even with ATLASSIAN_INSTALL_NO_OPEN=1 (tests)
#   ATLASSIAN_INSTALLER_TEST    1 = enable the test seams below; without it they are ignored, so a real run
#                               always asks in the dialog and talks to the real site. Never set it in a real
#                               environment: the test addresses would then receive the token. The stub
#                               credentials file is also ignored for the default Keychain service.
#   ATLASSIAN_TOKEN_STUB_FILE / ATLASSIAN_TEST_SITE_BASE / ATLASSIAN_TEST_GATEWAY_BASE / ATLASSIAN_TEST_PASTEBOARD
#                               test seams for the token prompt: a file holding the email and token (one per
#                               line), other site and gateway addresses, a private pasteboard to clear (need
#                               ATLASSIAN_INSTALLER_TEST=1)
set -euo pipefail

# Default download base (the prerelease copy is rewritten to point at /rc). Exactly one such line.
SITE_BASE_DEFAULT="https://wpp-jamie-mills.github.io/atlassian-mcp-server-site"

DEFAULT_SITES="wppchoreograph.atlassian.net wpp-dataandtech.atlassian.net"

# Colour only on a terminal, so agent and CI logs stay plain.
if [[ -t 1 && -t 2 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# printf, not echo -e, so backslashes in paths are shown as typed.
print_error() { printf '%b✗ %s%b\n' "$RED" "$1" "$NC" >&2; }
print_success() { printf '%b✓ %s%b\n' "$GREEN" "$1" "$NC"; }
print_warning() { printf '%b⚠ %s%b\n' "$YELLOW" "$1" "$NC"; }
print_step() { printf '%b→ %s%b\n' "$BLUE" "$1" "$NC"; }
die() {
  print_error "$1"
  exit 1
}

ATLASSIAN_KEYCHAIN_SERVICE="${ATLASSIAN_KEYCHAIN_SERVICE:-atlassian-mcp-server}"

# Physical path of $1 with symlinks resolved in the part that already exists, so the restricted-folder
# checks can't be dodged with symlinks, double slashes or a different spelling.
canonical_path() {
  local path="$1" rest="" dir
  while [[ ! -d "$path" ]]; do
    rest="/${path##*/}$rest"
    path="${path%/*}"
    [[ -n "$path" ]] || path="/"
  done
  dir="$(cd -P "$path" 2>/dev/null && pwd -P)" || return 1
  [[ "$dir" != "/" ]] || dir=""
  printf '%s%s\n' "$dir" "$rest"
}

lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

ATLASSIAN_TEMP_DIR=""
cleanup_temp() {
  if [[ -n "$ATLASSIAN_TEMP_DIR" && -d "$ATLASSIAN_TEMP_DIR" ]]; then rm -rf "$ATLASSIAN_TEMP_DIR"; fi
}

usage() {
  cat <<'EOF'
Atlassian MCP Server installer (macOS)

Usage:
  curl -fsSL https://wpp-jamie-mills.github.io/atlassian-mcp-server-site/install.sh | bash
  curl -fsSL <same url> | bash -s -- --site yourcompany.atlassian.net --site other.atlassian.net

Options:
  --site <site>  An Atlassian site to save a token for (repeatable), e.g. --site acme.atlassian.net. A bare
                 name like "acme" means acme.atlassian.net. Without it, the installer's default sites.
  --dir <path>   Data folder (default: ~/.atlassian-mcp-server). With a custom folder, set the same path in the
                 "Data folder" field of Claude Desktop's install dialog.
  --token        Ask for the email and API token of each site even if one is saved (to replace it). Needs a
                 terminal. Without --token, a run with no terminal or with --no-wait never opens the prompt
                 (it waits for a person): ask Claude to run atlassian_set_token instead.
  --status       Print the install state (Claude extension, sites, tokens, Rovo, what the server last
                 reported) and exit. Never prints a token.
  --no-wait      Open Claude Desktop's install dialog and exit without waiting for Claude to list the
                 extension. Exit 0 then means the installer finished its steps, not that Claude Desktop
                 installed the extension (check with --status).
  --uninstall    Remove the data folder and the saved tokens and Rovo sign-ins of its sites (asks first; with
                 no terminal, add --yes). Remove the extension itself in Claude Desktop: Settings → Extensions.
  --yes          Answer yes to the uninstall question.
  --help         Show this help.

This installer may need to quit and reopen Claude Desktop (only after an update). It asks first.

Environment: ATLASSIAN_MCP_HOME (same as --dir), ATLASSIAN_INSTALL_SITES (same as --site), ATLASSIAN_INSTALL_TTY
(where questions are read from; /dev/null means no terminal), ATLASSIAN_INSTALL_BASE (where the files are
downloaded from), ATLASSIAN_CLAUDE_APP (path to Claude.app). See the top of this script for the rest.
EOF
}

# A site as the server spells it: "acme" → acme.atlassian.net, "https://acme.atlassian.net/x" → acme.atlassian.net.
# Prints nothing for something that isn't a valid host name.
normalise_site() {
  local s
  s="$(lowercase "$1")"
  s="${s#https://}"
  s="${s%%[/?#]*}"
  [[ "$s" == *.* ]] || s="$s.atlassian.net"
  if [[ "$s" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ && ${#s} -le 253 ]]; then
    printf '%s\n' "$s"
  fi
}

token_present() {
  security find-generic-password -s "$ATLASSIAN_KEYCHAIN_SERVICE" -a "$1" >/dev/null 2>&1
}

# The site's cloud id from its public tenant_info endpoint (no credentials), or nothing.
cloud_id() {
  local base="https://$1" body
  if [[ "${ATLASSIAN_INSTALLER_TEST:-}" == "1" && "${ATLASSIAN_TEST_SITE_BASE:-}" =~ ^https?://[^\"[:space:]\\]+$ ]]; then
    base="$ATLASSIAN_TEST_SITE_BASE"
  fi
  body="$(curl -fsS --max-time 15 "$base/_edge/tenant_info" 2>/dev/null || true)"
  printf '%s' "$body" | sed -n 's/.*"cloudId"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F-]\{36\}\)".*/\1/p' | head -1
}

# Email and hidden-input token prompt, the check against the site (or the api.atlassian.com gateway for scoped
# tokens) and the Keychain save, in one process: the token never appears in argv, the environment or a file.
# Prints one JSON line ({"ok":true,"email":...,"apiBase":...} or {"ok":false,"reason":...}).
# Keep identical to TOKEN_PROMPT_JXA in src/token-prompt.ts (a test checks).
token_prompt() {
  local host="$1" cloud="$2" default_email="$3" site_base="" gateway_base=""
  # The addresses go into a curl config line, so only a plain http(s) URL is accepted.
  local url_re='^https?://[^"[:space:]\\]+$'
  if [[ "${ATLASSIAN_INSTALLER_TEST:-}" == "1" ]]; then
    [[ ! "${ATLASSIAN_TEST_SITE_BASE:-}" =~ $url_re ]] || site_base="$ATLASSIAN_TEST_SITE_BASE"
    [[ ! "${ATLASSIAN_TEST_GATEWAY_BASE:-}" =~ $url_re ]] || gateway_base="$ATLASSIAN_TEST_GATEWAY_BASE"
  fi
  osascript -l JavaScript - "$ATLASSIAN_KEYCHAIN_SERVICE" "$host" "$cloud" "$default_email" "$site_base" "$gateway_base" <<'JXA'
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("signal");

// Runs a program with input on stdin; returns its exit status and stdout. A program that exits before
// it has read its input (a dead curl) breaks the pipe: that comes back as a failure status.
function exec(path, args, input) {
  // Writing to a closed pipe raises SIGPIPE, which would kill this process; ignore it (SIG_IGN is 1).
  $.signal(13, 1);
  const task = $.NSTask.alloc.init;
  task.setLaunchPath($(path));
  task.setArguments($(args));
  const stdin = $.NSPipe.pipe;
  const stdout = $.NSPipe.pipe;
  task.setStandardInput(stdin);
  task.setStandardOutput(stdout);
  task.setStandardError($.NSPipe.pipe);
  task.launch;
  let wrote = true;
  try {
    stdin.fileHandleForWriting.writeData($(input).dataUsingEncoding($.NSUTF8StringEncoding));
  } catch (e) {
    wrote = false;
  }
  try { stdin.fileHandleForWriting.closeFile; } catch (e) {}
  const data = stdout.fileHandleForReading.readDataToEndOfFile;
  task.waitUntilExit;
  const status = task.terminationStatus;
  return { status: wrote || status !== 0 ? status : 1, stdout: ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)) || "" };
}

// The pasteboard the token was pasted from. Tests name a private one so they never touch the real clipboard.
function pasteboard(env, testMode) {
  const name = ObjC.unwrap(env.objectForKey("ATLASSIAN_TEST_PASTEBOARD"));
  return testMode && name ? $.NSPasteboard.pasteboardWithName(name) : $.NSPasteboard.generalPasteboard;
}

// Empties the pasteboard, but only if it still holds nothing but the token that was just pasted.
function clearPasteboardIfHolds(pb, token) {
  const held = ObjC.unwrap(pb.stringForType($.NSPasteboardTypeString));
  if (typeof held === "string" && held.trim() === token) pb.clearContents;
}

// GETs url with Basic auth. curl reads its config (including the credentials) from stdin, so they are never
// in argv. Every value in the config was checked to hold no quotes, backslashes or whitespace.
function probe(url, email, token) {
  let out;
  try {
    out = exec("/usr/bin/curl", ["-sS", "--max-time", "20", "-K", "-"],
      'url = "' + url + '"\nuser = "' + email + ":" + token + '"\nheader = "Accept: application/json"\nwrite-out = "\\n%{http_code}"\n');
  } catch (e) {
    return { status: 0, body: {} };
  }
  if (out.status !== 0) return { status: 0, body: {} };
  const lines = out.stdout.split("\n");
  const status = Number(lines.pop());
  let body = {};
  try { body = JSON.parse(lines.join("\n")) || {}; } catch (e) {}
  return { status: status, body: body };
}

// argv: service, host, cloudId, default email, site base and gateway base (the last two are used only in
// test mode). Prints one JSON line; the token never leaves this process except on the stdin of curl and
// security -i.
function run(argv) {
  const [service, host, cloudId, defaultEmail, siteBaseArg, gatewayBaseArg] = argv;
  // Both end up in a security -i command line, so allow nothing that could split it.
  const safe = /^[A-Za-z0-9._-]+$/;
  if (!safe.test(service || "") || !safe.test(host || "")) return JSON.stringify({ ok: false, reason: "store" });
  const env = $.NSProcessInfo.processInfo.environment;
  // Test seams (a credentials file, other API addresses, a private pasteboard) work only with this variable.
  // The credentials file is also refused for the default Keychain service, so a stray variable can't store a stub.
  const testMode = ObjC.unwrap(env.objectForKey("ATLASSIAN_INSTALLER_TEST")) === "1";
  const plainUrl = /^https?:\/\/[^"\s\\]+$/;
  if (testMode && (!plainUrl.test(siteBaseArg || "") || !plainUrl.test(gatewayBaseArg || "")))
    return JSON.stringify({ ok: false, reason: "network" });
  const siteBase = testMode ? siteBaseArg : "https://" + host;
  const gatewayBase = testMode ? gatewayBaseArg : "https://api.atlassian.com";
  const stubFile = testMode && service !== "atlassian-mcp-server" ? ObjC.unwrap(env.objectForKey("ATLASSIAN_TOKEN_STUB_FILE")) : "";
  let email;
  let token;
  if (stubFile) {
    const lines = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(stubFile, $.NSUTF8StringEncoding, null)).split("\n");
    email = (lines[0] || "").trim();
    token = (lines[1] || "").trim();
  } else {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    try { app.activate(); } catch (e) {}
    let answer;
    try {
      answer = app.displayDialog(
        "Enter the email address of your Atlassian account on " + host + ".",
        { withTitle: "Atlassian MCP Server", defaultAnswer: defaultEmail || "", buttons: ["Cancel", "Next"], defaultButton: "Next", cancelButton: "Cancel", withIcon: "note", givingUpAfter: 600 },
      );
    } catch (e) {
      return JSON.stringify({ ok: false, reason: "cancelled" });
    }
    if (answer.gaveUp) return JSON.stringify({ ok: false, reason: "timeout" });
    email = answer.textReturned.trim();
    if (!/^[^\s"\\:@]+@[^\s"\\:@]+\.[^\s"\\:@]+$/.test(email)) return JSON.stringify({ ok: false, reason: "email" });
    try {
      answer = app.displayDialog(
        "Paste the Atlassian API token for " + email + " on " + host + ". Create one at id.atlassian.com/manage-profile/security/api-tokens. It is stored in your macOS Keychain and never shown again.",
        { withTitle: "Atlassian MCP Server", defaultAnswer: "", hiddenAnswer: true, buttons: ["Cancel", "Save"], defaultButton: "Save", cancelButton: "Cancel", withIcon: "note", givingUpAfter: 600 },
      );
    } catch (e) {
      return JSON.stringify({ ok: false, reason: "cancelled" });
    }
    if (answer.gaveUp) return JSON.stringify({ ok: false, reason: "timeout" });
    token = answer.textReturned.trim();
  }
  // The pasted token may still be on the clipboard; remove it now that the dialog is gone.
  clearPasteboardIfHolds(pasteboard(env, testMode), token);
  if (!/^[^\s"\\:@]+@[^\s"\\:@]+\.[^\s"\\:@]+$/.test(email)) return JSON.stringify({ ok: false, reason: "email" });
  if (!/^[A-Za-z0-9_=+\/.-]{16,1024}$/.test(token)) return JSON.stringify({ ok: false, reason: "format" });

  // Classic tokens work against the site; scoped tokens only through the gateway. A site without Jira
  // answers 404 for the Jira check, so Confluence is asked instead.
  let apiBase = "site";
  let r = probe(siteBase + "/rest/api/3/myself", email, token);
  if (r.status === 404) r = probe(siteBase + "/wiki/rest/api/user/current", email, token);
  if ((r.status === 401 || r.status === 403) && /^[0-9a-f-]{36}$/.test(cloudId || "")) {
    let g = probe(gatewayBase + "/ex/jira/" + cloudId + "/rest/api/3/myself", email, token);
    if (g.status === 404) g = probe(gatewayBase + "/ex/confluence/" + cloudId + "/wiki/rest/api/user/current", email, token);
    if (g.status === 200) {
      r = g;
      apiBase = "gateway";
    }
  }
  if (r.status === 0) return JSON.stringify({ ok: false, reason: "network" });
  if (r.status === 401 || r.status === 403) return JSON.stringify({ ok: false, reason: "rejected" });
  if (r.status !== 200) return JSON.stringify({ ok: false, reason: "network", status: r.status });
  const accountId = typeof r.body.accountId === "string" ? r.body.accountId : "";
  const displayName = typeof r.body.displayName === "string" ? r.body.displayName : (typeof r.body.publicName === "string" ? r.body.publicName : "");

  let stored;
  try {
    stored = exec("/usr/bin/security", ["-i"], "add-generic-password -U -s " + service + " -a " + host + " -w " + token + "\n");
  } catch (e) {
    return JSON.stringify({ ok: false, reason: "store" });
  }
  if (stored.status !== 0) return JSON.stringify({ ok: false, reason: "store" });
  return JSON.stringify({ ok: true, email: email, apiBase: apiBase, accountId: accountId, displayName: displayName });
}
JXA
}

# Reads a value out of the prompt's JSON line, decoding it properly, with control characters removed.
json_field() {
  osascript -l JavaScript -e 'function run(argv) { try { const v = JSON.parse(argv[0])[argv[1]]; return typeof v === "string" ? v : ""; } catch (e) { return ""; } }' "$1" "$2" 2>/dev/null |
    LC_ALL=C tr -d '\000-\037\177' || true
}

# Prints sites.json with the site's record added or updated from the prompt's result (the email, which address
# the token works against, who it belongs to, the cloud id). Prints "invalid" if the file isn't JSON, so it is
# never overwritten. Same shape as src/sites.ts writes; it never holds a token.
merged_sites_json() {
  osascript -l JavaScript - "$1" "$2" "$3" "$4" <<'JXA'
ObjC.import("Foundation");
function run(argv) {
  const [file, host, cloudId, result] = argv;
  let r;
  try { r = JSON.parse(result); } catch (e) { return "invalid"; }
  let store = { sites: {} };
  const text = $.NSString.stringWithContentsOfFileEncodingError($(file), $.NSUTF8StringEncoding, null);
  if (!text.isNil()) {
    try {
      const parsed = JSON.parse(text.js);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "invalid";
      store = parsed;
      if (!store.sites || typeof store.sites !== "object" || Array.isArray(store.sites)) store.sites = {};
    } catch (e) {
      return "invalid";
    }
  }
  const record = Object.assign({}, store.sites[host] || {}, {
    host: host,
    email: r.email,
    apiBase: r.apiBase === "gateway" ? "gateway" : "site",
    savedAt: new Date().toISOString(),
  });
  if (cloudId) record.cloudId = cloudId;
  if (r.accountId) record.accountId = r.accountId;
  if (r.displayName) record.displayName = r.displayName;
  store.sites[host] = record;
  return JSON.stringify(store, null, 2);
}
JXA
}

save_site_record() {
  local data_dir="$1" host="$2" cloud="$3" result="$4" merged tmp
  merged="$(merged_sites_json "$data_dir/sites.json" "$host" "$cloud" "$result" || echo invalid)"
  if [[ "$merged" == invalid ]]; then
    print_warning "$data_dir/sites.json isn't valid JSON, so the details for $host weren't saved. Move it aside and run the installer again."
    return 1
  fi
  tmp="$data_dir/sites.json.$$.tmp"
  (umask 077 && printf '%s\n' "$merged" >"$tmp") && mv -f "$tmp" "$data_dir/sites.json"
}

# One line per site in sites.json: host, email, apiBase and whether Rovo is signed in, tab-separated.
list_site_records() {
  osascript -l JavaScript - "$1" <<'JXA' || true
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(argv[0]), $.NSUTF8StringEncoding, null);
  if (text.isNil()) return "";
  let sites;
  try { sites = JSON.parse(text.js).sites || {}; } catch (e) { return ""; }
  const clean = (v) => (typeof v === "string" ? v.replace(/[\u0000-\u001f\u007f-\u009f\t]/g, "").slice(0, 200) : "");
  return Object.keys(sites)
    .filter((h) => /^[a-z0-9.-]+$/.test(h))
    .map((h) => [h, clean(sites[h].email), clean(sites[h].apiBase), sites[h].rovoSession ? "yes" : "no"].join("\t"))
    .join("\n");
}
JXA
}

# Version of the Atlassian extension that Claude Desktop lists as installed, or "none".
claude_extension_version() {
  osascript -l JavaScript - "$1" <<'JXA' || echo none
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(
    $(argv[0]).stringByResolvingSymlinksInPath,
    $.NSUTF8StringEncoding,
    null,
  );
  if (text.isNil()) return "none";
  try {
    const all = JSON.parse(text.js).extensions || {};
    const key = Object.keys(all).find((k) => /(^|\.)atlassian-mcp-server$/.test(k));
    return key && all[key].version ? String(all[key].version) : "none";
  } catch (e) {
    return "none";
  }
}
JXA
}

is_plain_file() { [[ -f "$1" && ! -L "$1" ]]; }

# True when an interrupted run's temp folder holds only what this script puts there.
download_leftover_is_ours() {
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [[ -e "$f" || -L "$f" ]] || continue
    case "${f##*/}" in
      latest.mcpb | latest.mcpb.sha256 | latest.version) is_plain_file "$f" || return 1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# Reads a yes/no answer from the terminal (default no). Without a usable terminal the answer is no.
# The answer source must be a regular file (the tests' scripted answers) or a terminal; /dev/null or another
# device can't answer, so nothing is printed for it.
can_answer() {
  local p="$ATLASSIAN_INSTALL_TTY_PATH"
  [[ -r "$p" ]] || return 1
  [[ -f "$p" ]] && return 0
  [[ -c "$p" ]] || return 1
  { [[ -t 3 ]]; } 2>/dev/null 3<"$p"
}

ask_yes_no() {
  local answer=""
  can_answer || return 1
  printf '%s [y/N] ' "$1"
  { read -r -t 600 answer <"$ATLASSIAN_INSTALL_TTY_PATH"; } 2>/dev/null || true
  case "$(lowercase "$answer")" in y | yes) return 0 ;; *) return 1 ;; esac
}

app_running() { pgrep -x "$1" >/dev/null 2>&1; }

# True when this installer runs inside the app at $1 (its .app folder): any process up the parent chain has its
# executable under that folder. Quitting the app would then end the installer, and the terminal it runs in.
# Best effort only, so the question is only ever asked after an explicit yes, never assumed from this check.
inside_app() {
  local app_path="${1%/}" pid="$$" line ppid comm i
  for ((i = 0; i < 64; i++)); do
    line="$(ps -o ppid=,comm= -p "$pid" 2>/dev/null || true)"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || return 1
    ppid="${line%%[[:space:]]*}"
    comm="${line#"$ppid"}"
    comm="${comm#"${comm%%[![:space:]]*}"}"
    case "$comm" in "$app_path"/*) return 0 ;; esac
    [[ "$ppid" =~ ^[0-9]+$ && "$ppid" -gt 1 && "$ppid" != "$pid" ]] || return 1
    pid="$ppid"
  done
  return 1
}

# Quits an app politely and waits (up to ~30s) for it to go. Returns 1 if it is still running, if the quit
# was refused, or if this installer runs inside the app. $2 is the app's .app folder.
quit_app() {
  local app="$1" app_path="$2" i quit_ok=true limit=60
  if inside_app "$app_path"; then
    print_warning "This installer is running inside $app, so it won't quit it (that would end the install). Quit and reopen $app yourself."
    return 1
  fi
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || quit_ok=false
  [[ "$quit_ok" == true ]] || limit=4
  for ((i = 0; i < limit; i++)); do
    app_running "$app" || return 0
    sleep 0.5
  done
  [[ "$quit_ok" == true ]] || print_warning "macOS refused the quit request. It may need your permission: in System Settings > Privacy & Security > Automation, allow your terminal to control $app, then run the installer again (or quit $app yourself)."
  [[ "$quit_ok" != true ]] || print_warning "$app is still running after 30 seconds. Quit it yourself."
  return 1
}

# What the server last wrote to status.json (non-secret fields only), as "key: value" lines.
print_server_status() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "status_file: missing"
    return 0
  fi
  echo "status_file: $file"
  osascript -l JavaScript - "$file" <<'JXA' || echo "status: unreadable"
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(argv[0]), $.NSUTF8StringEncoding, null);
  if (text.isNil()) return "status: unreadable";
  let s;
  try { s = JSON.parse(text.js); } catch (e) { return "status: unreadable"; }
  const clean = (v) => (typeof v === "string" || typeof v === "number" || typeof v === "boolean" ? String(v).replace(/[\u0000-\u001f\u007f-\u009f]/g, "").slice(0, 300) : "");
  const out = ["server_version: " + clean(s.serverVersion)];
  const at = Date.parse(s.updatedAt);
  out.push("status_age_seconds: " + (isNaN(at) ? "unknown" : Math.max(0, Math.round((Date.now() - at) / 1000))));
  for (const site of Array.isArray(s.sites) ? s.sites : []) {
    if (!site || typeof site.host !== "string") continue;
    out.push("server_site " + clean(site.host) + ": token=" + clean(site.token) + " jira=" + clean(site.jira) + " confluence=" + clean(site.confluence) + " rovo=" + clean(site.rovo));
    if (site.nextStep) out.push("  next_step: " + clean(site.nextStep));
  }
  return out.join("\n");
}
JXA
}

print_status() {
  local data_dir="$1" claude_support="$2" sites="$3" host line email api rovo seen=" "
  echo "data_dir: $data_dir"
  echo "claude_extension: $(claude_extension_version "$claude_support/extensions-installations.json")"
  while IFS=$'\t' read -r host email api rovo; do
    [[ -n "$host" ]] || continue
    seen+="$host "
    line="site $host: token=$(token_present "$host" && echo present || echo missing)"
    [[ -z "$email" ]] || line+=" email=$email"
    [[ -z "$api" ]] || line+=" api=$api"
    line+=" rovo=$rovo"
    echo "$line"
  done < <(list_site_records "$data_dir/sites.json")
  for host in $sites; do
    case "$seen" in *" $host "*) continue ;; esac
    echo "site $host: token=$(token_present "$host" && echo present || echo missing) rovo=no"
  done
  print_server_status "$data_dir/status.json"
}

main() {
  [[ -n "${HOME:-}" ]] || die "HOME isn't set, so the installer can't find your home folder"
  local data_dir="" force_token=false status_only=false no_wait=false uninstall=false yes=false site_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -ge 2 && -n "$2" ]] || die "--dir needs a folder path"
        data_dir="$2"
        shift 2
        ;;
      --dir=*)
        data_dir="${1#--dir=}"
        [[ -n "$data_dir" ]] || die "--dir needs a folder path"
        shift
        ;;
      --site)
        [[ $# -ge 2 && -n "$2" ]] || die "--site needs a site, e.g. acme.atlassian.net"
        site_args+=("$2")
        shift 2
        ;;
      --site=*)
        [[ -n "${1#--site=}" ]] || die "--site needs a site, e.g. acme.atlassian.net"
        site_args+=("${1#--site=}")
        shift
        ;;
      --token)
        force_token=true
        shift
        ;;
      --status)
        status_only=true
        shift
        ;;
      --no-wait)
        no_wait=true
        shift
        ;;
      --uninstall)
        uninstall=true
        shift
        ;;
      --yes | -y)
        yes=true
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *) die "Unknown argument: $1 (try --help)" ;;
    esac
  done

  # It goes into a security command line in the token prompt, so allow nothing that could split it.
  [[ "$ATLASSIAN_KEYCHAIN_SERVICE" =~ ^[A-Za-z0-9._-]+$ ]] || die "ATLASSIAN_KEYCHAIN_SERVICE may only contain letters, digits, dots, underscores and hyphens"

  # The sites: --site wins (each value may hold several, separated by commas), then ATLASSIAN_INSTALL_SITES
  # (spaces or commas), then the defaults.
  local s n sites="" site_list=() parts=()
  if [[ ${#site_args[@]} -gt 0 ]]; then
    for s in "${site_args[@]}"; do
      IFS=',' read -r -a parts <<<"$s"
      site_list+=("${parts[@]}")
    done
  else
    IFS=$' ,\t' read -r -a site_list <<<"${ATLASSIAN_INSTALL_SITES:-$DEFAULT_SITES}"
  fi
  for s in "${site_list[@]}"; do
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    [[ -n "$s" ]] || continue
    n="$(normalise_site "$s")"
    [[ -n "$n" ]] || die "Not a valid Atlassian site: $s"
    case " $sites " in *" $n "*) ;; *) sites="${sites:+$sites }$n" ;; esac
  done
  [[ -n "$sites" ]] || die "No Atlassian site to set up (give one with --site)"

  local default_dir="${HOME%/}/.atlassian-mcp-server"
  [[ -n "$data_dir" ]] || data_dir="${ATLASSIAN_MCP_HOME:-$default_dir}"
  # Expand a leading ~ (the shell doesn't when the path arrives quoted or via the environment).
  if [[ "$data_dir" == \~ || "$data_dir" == \~/* ]]; then data_dir="$HOME${data_dir:1}"; fi
  data_dir="${data_dir%/}"
  [[ "$data_dir" == /* ]] || die "The data folder must be an absolute path: $data_dir"
  case "/$data_dir/" in
    */../* | */./*) die "The data folder can't contain . or .. segments: $data_dir" ;;
  esac
  local claude_support="$HOME/Library/Application Support/Claude"
  # Compare physical, lower-cased paths: macOS volumes are case-insensitive by default.
  local canon_data canon_default canon_home p canon_p
  canon_data="$(lowercase "$(canonical_path "$data_dir")")" || die "Can't resolve the data folder: $data_dir"
  canon_default="$(lowercase "$(canonical_path "$default_dir")")" || die "Can't resolve $default_dir"
  canon_home="$(lowercase "$(canonical_path "$HOME")")" || die "Can't resolve your home folder"
  for p in "$claude_support/Claude Extensions" /Applications /System /Library /usr /bin /sbin /etc /private/etc /opt; do
    [[ -e "$p" ]] || continue
    canon_p="$(lowercase "$(canonical_path "$p")")"
    if [[ "$canon_data" == "$canon_p" || "$canon_data" == "$canon_p/"* ]]; then
      die "Can't use a restricted location as the data folder: $data_dir"
    fi
  done
  [[ "$canon_data" != "$canon_home" ]] || die "Can't use your home folder itself (a restricted location) as the data folder"
  local is_default=false
  if [[ "$canon_data" == "$canon_default" ]]; then
    is_default=true
    data_dir="$default_dir"
  fi

  ATLASSIAN_INSTALL_TTY_PATH="${ATLASSIAN_INSTALL_TTY:-/dev/tty}"
  local claude_app="${ATLASSIAN_CLAUDE_APP:-/Applications/Claude.app}"
  local install_base="${ATLASSIAN_INSTALL_BASE:-$SITE_BASE_DEFAULT}"
  install_base="${install_base%/}"
  # Under curl | bash there is no local install.sh, so the pointers to --status spell out the whole command.
  # Every value is shell-quoted (printf %q) so the printed command can be pasted even when a path holds a
  # space, $, backtick, quote or backslash.
  local q_base q_dir
  printf -v q_base '%q' "$install_base"
  printf -v q_dir '%q' "$data_dir"
  local status_cmd="curl -fsSL $q_base/install.sh | bash -s -- --status"
  if [[ "$is_default" != true ]]; then status_cmd+=" --dir $q_dir"; fi

  if [[ "$status_only" == true ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
    print_status "$data_dir" "$claude_support" "$sites"
    return 0
  fi

  if [[ "$uninstall" == true ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
    [[ -d "$data_dir" ]] || die "Nothing to remove: $data_dir doesn't exist"
    [[ -e "$data_dir/.atlassian-mcp-home" ]] || die "$data_dir isn't an Atlassian MCP Server data folder; leaving it alone"
    local all_sites="$sites" host rest
    while IFS=$'\t' read -r host rest; do
      [[ -n "$host" ]] || continue
      case " $all_sites " in *" $host "*) ;; *) all_sites="$all_sites $host" ;; esac
    done < <(list_site_records "$data_dir/sites.json")
    if [[ "$yes" != true ]] && ! ask_yes_no "Remove $data_dir and the saved tokens and Rovo sign-ins for: $all_sites?"; then
      die "Not removed (with no terminal, add --yes)"
    fi
    local head parts i
    for host in $all_sites; do
      security delete-generic-password -s "$ATLASSIAN_KEYCHAIN_SERVICE" -a "$host" >/dev/null 2>&1 || true
      # A Rovo sign-in too long for one item is stored in parts (see src/keychain.ts): "chunked:<n>", then
      # items <site>.1 to <site>.<n>.
      head="$(security find-generic-password -s "$ATLASSIAN_KEYCHAIN_SERVICE-rovo" -a "$host" -w 2>/dev/null || true)"
      parts=0
      [[ ! "$head" =~ ^chunked:([1-9][0-9]{0,3})$ ]] || parts="${BASH_REMATCH[1]}"
      security delete-generic-password -s "$ATLASSIAN_KEYCHAIN_SERVICE-rovo" -a "$host" >/dev/null 2>&1 || true
      for ((i = 1; i <= parts; i++)); do
        security delete-generic-password -s "$ATLASSIAN_KEYCHAIN_SERVICE-rovo" -a "$host.$i" >/dev/null 2>&1 || true
      done
    done
    rm -rf "${data_dir:?}"
    print_success "Removed $data_dir and the saved tokens"
    echo "To remove the extension itself: Claude Desktop → Settings → Extensions → Atlassian MCP Server → Uninstall."
    return 0
  fi

  echo ""
  printf '%b%s%b\n' "$BLUE" "Atlassian MCP Server installer" "$NC"
  printf '%s\n' "Give Claude every Jira, Confluence and Rovo API"
  echo ""
  print_warning "This installer may need to quit and reopen Claude Desktop (only after an update). It asks first."
  echo ""

  print_step "Checking prerequisites..."
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
  [[ -d "$claude_app" ]] || die "Claude.app not found at: $claude_app (install Claude Desktop first)"
  local tool
  for tool in curl shasum osascript open security awk sed; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not available"
  done
  print_success "macOS and Claude Desktop found"

  # The data folder must be new, empty, or one of ours.
  if [[ -e "$data_dir" && ! -d "$data_dir" ]]; then die "Not a folder: $data_dir"; fi
  if [[ -d "$data_dir" ]]; then
    local ours=false
    if [[ -e "$data_dir/.atlassian-mcp-home" || -e "$data_dir/sites.json" || -e "$data_dir/status.json" ]]; then ours=true; fi
    if [[ "$ours" != true && -n "$(find "$data_dir" -mindepth 1 -maxdepth 1 ! -name '.download.*' ! -name .DS_Store 2>/dev/null)" ]]; then
      die "That folder is not empty and isn't an Atlassian MCP Server data folder: $data_dir"
    fi
    [[ -w "$data_dir" ]] || die "That folder isn't writable: $data_dir"
    # Leftovers from an interrupted run: only our own temp folders, untouched for 15 minutes.
    local leftover
    for leftover in "$data_dir"/.download.??????; do
      [[ -d "$leftover" && ! -L "$leftover" ]] || continue
      [[ -z "$(find "$leftover" -maxdepth 0 -mmin -15 2>/dev/null)" ]] || continue
      ! download_leftover_is_ours "$leftover" || rm -rf "$leftover"
    done
  else
    mkdir -p "$data_dir" || die "Couldn't create $data_dir"
    chmod 700 "$data_dir" || die "Couldn't set permissions on $data_dir"
  fi
  # Mark the folder as ours straight away, so a re-run after an interruption recognises it.
  touch "$data_dir/.atlassian-mcp-home"
  print_success "Data folder: $data_dir"

  # Download into a temp folder and verify before anything is changed.
  ATLASSIAN_TEMP_DIR="$(mktemp -d "$data_dir/.download.XXXXXX")" || die "Couldn't create a temporary folder"
  trap cleanup_temp EXIT

  print_step "Downloading the latest extension..."
  curl -fsSL "$install_base/latest.mcpb" -o "$ATLASSIAN_TEMP_DIR/latest.mcpb" || die "Download failed: $install_base/latest.mcpb"
  curl -fsSL "$install_base/latest.mcpb.sha256" -o "$ATLASSIAN_TEMP_DIR/latest.mcpb.sha256" || die "Download failed: $install_base/latest.mcpb.sha256"
  local version=""
  if curl -fsSL "$install_base/latest.version" -o "$ATLASSIAN_TEMP_DIR/latest.version" 2>/dev/null; then
    version="$(tr -d '[:space:]' <"$ATLASSIAN_TEMP_DIR/latest.version")"
  fi
  [[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "The site's latest.version isn't a version number"

  local expected actual
  expected="$(awk 'NR == 1 { print tolower($1) }' "$ATLASSIAN_TEMP_DIR/latest.mcpb.sha256")"
  # Hash from stdin: shasum escapes file names containing backslashes and prefixes the hash with "\".
  actual="$(shasum -a 256 <"$ATLASSIAN_TEMP_DIR/latest.mcpb" | awk '{ print $1 }')"
  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "$expected" != "$actual" ]]; then
    print_error "Checksum mismatch — nothing was installed"
    print_error "Expected: ${expected:-<none>}"
    print_error "Got:      $actual"
    print_error "This can happen for up to about 10 minutes while a new release propagates; wait and run the installer again."
    exit 1
  fi
  print_success "Downloaded and verified${version:+ version $version}"

  local name
  for name in latest.mcpb latest.mcpb.sha256 latest.version; do
    if [[ -d "$data_dir/$name" ]]; then die "$data_dir/$name is a folder; move it out of the way and run the installer again"; fi
  done
  mv -f "$ATLASSIAN_TEMP_DIR/latest.mcpb" "$data_dir/latest.mcpb"
  mv -f "$ATLASSIAN_TEMP_DIR/latest.mcpb.sha256" "$data_dir/latest.mcpb.sha256"
  if [[ -n "$version" ]]; then mv -f "$ATLASSIAN_TEMP_DIR/latest.version" "$data_dir/latest.version"; fi

  # API tokens: kept only in the Keychain, one per site. Ask when a site has none (or with --token), and only
  # with a person at a terminal: the prompt is a dialog that waits, and an agent's run must return quickly.
  local host saved_names="" missing_sites=""
  if [[ "${ATLASSIAN_INSTALL_SKIP_TOKEN:-}" == "1" ]]; then
    print_step "Skipping the token step (ATLASSIAN_INSTALL_SKIP_TOKEN=1)"
  fi
  for host in $sites; do
    if [[ "${ATLASSIAN_INSTALL_SKIP_TOKEN:-}" == "1" ]]; then
      token_present "$host" || missing_sites="${missing_sites:+$missing_sites }$host"
      continue
    fi
    if ! { [[ "$force_token" == true ]] && can_answer; } && ! { [[ "$no_wait" != true ]] && can_answer && ! token_present "$host"; }; then
      if token_present "$host"; then
        print_success "$host: an API token is already saved in the Keychain"
      else
        missing_sites="${missing_sites:+$missing_sites }$host"
      fi
      continue
    fi
    echo ""
    print_step "$host: your Atlassian email and an API token are needed (saved to your Keychain, never shown in chat)."
    echo "  Create a token at https://id.atlassian.com/manage-profile/security/api-tokens"
    local cloud
    cloud="$(cloud_id "$host")"
    if [[ -z "$cloud" ]]; then
      print_warning "$host: couldn't find this site (no cloud id). Check the name; skipping it."
      missing_sites="${missing_sites:+$missing_sites }$host"
      continue
    fi
    if [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" != "1" && -z "$saved_names" ]]; then
      open "https://id.atlassian.com/manage-profile/security/api-tokens" >/dev/null 2>&1 || true
    fi
    local result="" default_email="" got=false _attempt
    default_email="$(list_site_records "$data_dir/sites.json" | awk -F '\t' -v h="$host" '$1 == h { print $2 }')"
    for _attempt in 1 2 3; do
      touch "$ATLASSIAN_TEMP_DIR" 2>/dev/null || true
      result="$(token_prompt "$host" "$cloud" "$default_email" || true)"
      case "$result" in
        *'"ok":true'*)
          got=true
          save_site_record "$data_dir" "$host" "$cloud" "$result" || true
          local who api
          who="$(json_field "$result" displayName)"
          api="$(json_field "$result" apiBase)"
          print_success "$host: token saved to the Keychain${who:+ ($who)}${api:+, $([[ "$api" == gateway ]] && echo "scoped token, via api.atlassian.com" || echo "classic token")}"
          saved_names="${saved_names:+$saved_names, }${who:-$host}"
          break
          ;;
        *'"reason":"cancelled"'*)
          print_warning "$host: cancelled. Ask Claude to run atlassian_set_token for it later."
          break
          ;;
        *'"reason":"timeout"'*)
          print_warning "$host: the prompt timed out, so no token was saved."
          break
          ;;
        *'"reason":"email"'*) print_warning "That doesn't look like an email address. Try again." ;;
        *'"reason":"format"'*) print_warning "That doesn't look like an Atlassian API token. Try again." ;;
        *'"reason":"rejected"'*) print_warning "Atlassian rejected that email and token for $host. Check the token is current and belongs to that email, then try again." ;;
        *'"reason":"network"'*) print_warning "Couldn't reach $host to check the token. Check your connection, then try again." ;;
        *'"reason":"store"'*) print_warning "Couldn't save the token to the Keychain." ;;
        *) print_warning "The prompt failed or ended without a result, so no token was saved." ;;
      esac
    done
    [[ "$got" == true ]] || missing_sites="${missing_sites:+$missing_sites }$host"
  done

  local ext_file="$claude_support/extensions-installations.json"
  local before
  before="$(claude_extension_version "$ext_file")"

  # Claude already lists this version: don't open the install dialog again. With --dir the extension's
  # "Data folder" setting must be set in the dialog, so it opens even then.
  local already_installed=false reopen_same=false
  [[ -n "$version" && "$before" == "$version" && "$is_default" != true ]] && reopen_same=true
  if [[ -n "$version" && "$before" == "$version" && "$is_default" == true ]]; then
    already_installed=true
    print_success "Atlassian MCP Server $version is already installed"
  elif [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" == "1" ]]; then
    print_step "Would open: open -a \"$claude_app\" \"$data_dir/latest.mcpb\""
  else
    print_step "Opening Claude Desktop's install dialog..."
    open -a "$claude_app" "$data_dir/latest.mcpb" ||
      print_warning "Couldn't open it automatically. Double-click $data_dir/latest.mcpb to install."
  fi

  if [[ "$already_installed" != true ]]; then
    echo ""
    echo "In the install dialog:"
    if [[ "$is_default" != true ]]; then
      printf '  1. Set "Data folder" to: %b%s%b\n' "$BLUE" "$data_dir" "$NC"
      echo "  2. Click Install."
    else
      echo "  Leave the settings as they are and click Install."
    fi
  fi

  # Wait until Claude lists the extension at the new version, instead of asking for Enter.
  local wait_secs="${ATLASSIAN_INSTALL_WAIT_SECS:-}"
  if [[ -z "$wait_secs" ]]; then
    if [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" == "1" ]]; then wait_secs=0; else wait_secs=600; fi
  fi
  [[ "$wait_secs" =~ ^[0-9]+$ ]] || wait_secs=600
  if [[ "$no_wait" == true || "$already_installed" == true ]]; then wait_secs=0; fi
  local installed="none" waited=0
  while :; do
    touch "$ATLASSIAN_TEMP_DIR" 2>/dev/null || true
    installed="$(claude_extension_version "$ext_file")"
    if [[ -n "$version" ]]; then
      [[ "$installed" != "$version" ]] || break
    elif [[ "$installed" != "none" && "$installed" != "$before" ]]; then
      break
    fi
    [[ "$waited" -lt "$wait_secs" ]] || break
    [[ "$waited" -ne 0 ]] || print_step "Waiting for you to click Install in Claude Desktop..."
    sleep 2
    waited=$((waited + 2))
  done

  echo ""
  local finished=false
  if [[ "$reopen_same" == true ]]; then
    print_warning "Finish the dialog (set Data folder), then run: $status_cmd"
  elif [[ -n "$version" && "$installed" == "$version" ]] || [[ -z "$version" && "$installed" != "none" && "$installed" != "$before" ]]; then
    finished=true
    print_success "Claude Desktop lists Atlassian MCP Server $installed"
    # An upgrade: Claude may still be running the old server. Restart only if the user agrees.
    if [[ "$before" != "none" && "$before" != "$installed" && "${ATLASSIAN_INSTALL_NO_OPEN:-}" != "1" ]] && app_running Claude; then
      touch "$ATLASSIAN_TEMP_DIR" 2>/dev/null || true
      if inside_app "$claude_app"; then
        print_warning "This installer is running inside Claude Desktop, so it won't quit it. Restart Claude Desktop yourself to use the new version."
      elif ask_yes_no "Claude Desktop may still be running the old version. Quit and reopen it now?"; then
        if quit_app Claude "$claude_app"; then
          open -a "$claude_app" || print_warning "Couldn't reopen Claude Desktop; open it yourself."
        else
          print_warning "Claude Desktop didn't quit; restart it yourself to use the new version."
        fi
      else
        print_warning "Restart Claude Desktop yourself to use the new version."
      fi
    fi
    if [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" != "1" || "${ATLASSIAN_INSTALL_NOTIFY:-}" == "1" ]]; then
      local note="Atlassian MCP Server $installed is installed"
      [[ -z "$saved_names" ]] || note="Atlassian connected as $saved_names"
      # The text travels as an argument, never as AppleScript source, so quotes and backslashes stay text.
      osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Atlassian MCP Server"' -e 'end run' -- "$note" >/dev/null 2>&1 || true
    fi
  elif [[ "$wait_secs" -gt 0 ]]; then
    print_warning "Claude Desktop doesn't list the new version yet (installed: $installed). Finish the install dialog, then run: $status_cmd"
  else
    print_step "Not waiting for Claude Desktop to finish; run this to check: $status_cmd"
  fi

  echo ""
  if [[ "$finished" == true || "$already_installed" == true ]]; then print_success "Done."; else print_warning "Install not confirmed."; fi
  if [[ -n "$missing_sites" ]]; then
    echo "No API token yet for: $missing_sites"
    echo "  Ask Claude to run atlassian_set_token for each (a secure prompt), or run the installer again in a terminal."
  fi
  echo "Next, in Claude:"
  echo "  1. Ask \"Is Atlassian connected?\" (it runs atlassian_ensure_ready and tells you the next step)."
  echo "  2. For Rovo search and the Teamwork Graph, ask Claude to sign in to Rovo for each site (a browser sign-in per site)."
  if [[ "$is_default" == true ]]; then
    echo "To check the state: run the same command with --status. To update later, run the same command again."
  else
    printf 'To check the state: run the same command with --status (keep --dir %s). To update, run it again with --dir %s\n' "$q_dir" "$q_dir"
  fi
  echo ""
}

main "$@"
