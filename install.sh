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
# Where Claude Desktop can't use the extension, the same release as a Claude Desktop mcpServers entry (it asks for
# the tokens too, with a terminal; it never quits Claude Desktop, but opens it if it isn't running):
#   curl -fsSL <same url> | bash -s -- --entry
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
#   ATLASSIAN_MULTI_MCP_DATA_DIR  the mcpServers entry's own folder (default ~/Library/Application Support/
#                               atlassian-mcp-server)
#   ATLASSIAN_CLAUDE_CONFIG / ATLASSIAN_CLAUDE_LOGS  Claude Desktop's config file and log folder (tests)
#   ATLASSIAN_BUN_CANDIDATES    where to look for Bun, separated by colons (tests); ATLASSIAN_BREW: brew's path, or
#                               none (tests)
#   ATLASSIAN_BUN_BASE / ATLASSIAN_BUN_SHA256 / ATLASSIAN_BUN_ARCH  Bun's download (need ATLASSIAN_INSTALLER_TEST=1)
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
  --yes          Answer yes to the uninstall question (with --entry: the go-ahead to change Claude Desktop's config).
  --help         Show this help.

Where Claude Desktop can't use the extension, the same release runs as a Claude Desktop mcpServers entry:
  --entry        Install (or update) the released server and add the atlassian-multi-mcp entry to Claude
                 Desktop's claude_desktop_config.json (it asks first and keeps a backup; with no terminal, --yes
                 is that go-ahead). Stable releases only. Never quits Claude Desktop: quit and reopen it yourself.
  --install-bun  With --entry: the go-ahead to install Bun, which the entry runs with, if it is missing: with
                 Homebrew on Apple silicon if you have it, else Bun's own release from GitHub (pinned, checked against its SHA-256)
                 into ~/.bun/bin. Separate from --yes.
  --entry --uninstall  Remove only that entry (if it runs this installer's release) and the installed release.

This installer may need to quit and reopen Claude Desktop (only after an extension update). It asks first.

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

# The extension's "Enable write tools" setting: on, off (its default) or none (no extension). Reads only that one
# value from Claude Desktop's settings file for the extension.
claude_extension_writes() {
  osascript -l JavaScript - "$1" <<'JXA' || echo unknown
ObjC.import("Foundation");
function read(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(path).stringByResolvingSymlinksInPath, $.NSUTF8StringEncoding, null);
  return text.isNil() ? undefined : JSON.parse(text.js);
}
function run(argv) {
  try {
    const all = (read(argv[0] + "/extensions-installations.json") || {}).extensions || {};
    const key = Object.keys(all).find((k) => /(^|\.)atlassian-mcp-server$/.test(k));
    if (!key || !/^[A-Za-z0-9._-]+$/.test(key)) return "none";
    const settings = read(argv[0] + "/Claude Extensions Settings/" + key + ".json") || {};
    return (settings.userConfig || {}).enable_write_tools === true ? "on" : "off";
  } catch (e) {
    return "unknown";
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
      latest.mcpb | latest.mcpb.sha256 | latest.version | config.??????) is_plain_file "$f" || return 1 ;;
      # An --entry run unpacks the release here before installing it.
      release) [[ -d "$f" && ! -L "$f" ]] || return 1 ;;
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
  local ext_version
  ext_version="$(claude_extension_version "$claude_support/extensions-installations.json")"
  echo "claude_extension: $ext_version"
  # Before 1.3.0 there was no setting: the write tools were always on.
  if [[ "$ext_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && version_older "$ext_version" "1.3.0"; then
    echo "claude_extension_write_tools: on (always, before 1.3.0)"
  else
    echo "claude_extension_write_tools: $(claude_extension_writes "$claude_support")"
  fi
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

# ---- The mcpServers entry (--entry) ----
#
# For where Claude Desktop can't use the extension: the same release runs as a plain "mcpServers" entry in
# claude_desktop_config.json (README, "Install as a Claude Desktop mcpServers entry"). The release installs itself with
# its own install-release (src/install-release.ts) into <entry data>/server and prints its launcher; this installer
# adds the entry that runs it. It needs Bun: with the person's go-ahead it installs Bun with Homebrew, or without
# Homebrew from Bun's GitHub release at a pinned version, checked against a pinned SHA-256. It never quits Claude
# Desktop.

ENTRY_NAME="atlassian-multi-mcp"
LAUNCHER_NAME="atlassian-multi-mcp"
# Keep equal to src/run-mode.ts MIN_BUN (a test checks).
BUN_MIN="1.3.0"
# The Bun the download route installs; keep equal to CI's (a test checks). scripts/bun-pins.mjs prints the hashes.
BUN_VERSION="1.4.4"
BUN_SHA256_AARCH64="c240d7f0ccb90c263a849fcdb09b7ee62630d921348ed6aafda86b9d577bc510"
BUN_SHA256_X64="50a3491f73abc2fe81673171a85762d3bc2cc1680ccecadd983de99adf77977e"
BUN_SHA256_X64_BASELINE="d4a155adfbfd09155eb3ba05c9e3a544f39297d7a68616d3c7759f67ab5c47dc"
ENTRY_SYSTEM_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Succeeds when version $1 (X.Y.Z; anything after - or + ignored) is at least $2.
version_at_least() {
  awk -v a="${1%%[-+]*}" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+(\.[0-9]+)*$/) exit 1
    n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0
  }'
}

# Succeeds when release $1 is older than $2; a pre-release (X.Y.Z-rc.N) is older than its X.Y.Z.
version_older() {
  local a="${1%%-*}" b="${2%%-*}"
  [[ "$1" != "$2" ]] || return 1
  if [[ "$a" != "$b" ]]; then
    ! version_at_least "$a" "$b"
  elif [[ "$1" == *-* && "$2" == *-* ]]; then
    [[ "$1" < "$2" ]]
  else
    [[ "$1" == *-* ]]
  fi
}

# The entry's own data folder, as src/run-mode.ts entryDataDir finds it: ATLASSIAN_MULTI_MCP_DATA_DIR trimmed, ~
# expanded, "." and ".." resolved and "//" collapsed (as Node's path.resolve does), or the default when it is unset,
# a placeholder or not absolute. The two must agree, or the entry's command and this installer's would differ.
entry_data_dir() {
  local d="${ATLASSIAN_MULTI_MCP_DATA_DIR:-}" part parts=() out=()
  d="${d#"${d%%[![:space:]]*}"}"
  d="${d%"${d##*[![:space:]]}"}"
  if [[ "$d" == \~ || "$d" == \~/* ]]; then d="${HOME%/}${d:1}"; fi
  if [[ -z "$d" || "$d" == '${'* || "$d" != /* ]]; then
    d="${HOME%/}/Library/Application Support/atlassian-mcp-server"
  fi
  IFS=/ read -r -a parts <<<"$d"
  for part in "${parts[@]}"; do
    case "$part" in
      '' | .) ;;
      ..) [[ ${#out[@]} -eq 0 ]] || unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  if [[ ${#out[@]} -eq 0 ]]; then echo /; else printf '/%s' "${out[@]}"; echo; fi
}

# The Bun the entry would run with, or nothing: where its launcher looks (src/launcher.ts). Always succeeds.
find_bun() {
  local candidates=() candidate
  if [[ -n "${ATLASSIAN_BUN_CANDIDATES+set}" ]]; then
    IFS=: read -r -a candidates <<<"$ATLASSIAN_BUN_CANDIDATES"
  else
    candidates=("$(command -v bun 2>/dev/null || true)" /opt/homebrew/bin/bun /usr/local/bin/bun "${HOME%/}/.bun/bin/bun")
  fi
  [[ ${#candidates[@]} -gt 0 ]] || return 0
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]]; then
      # A relative PATH entry gives a relative path: the entry and this installer run Bun from other folders.
      [[ "$candidate" == /* ]] || candidate="$(cd "$(dirname "$candidate")" && pwd -P)/${candidate##*/}"
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

bun_version() { "$1" --version 2>/dev/null | head -n 1 | tr -d '[:space:]' || true; }

# Homebrew's brew, or nothing. ATLASSIAN_BREW names one (tests; "none" means there is none). Always succeeds.
# Only on Apple silicon: Homebrew has no Bun bottle for Intel Macs, so it would build Bun from source.
find_brew() {
  if [[ -n "${ATLASSIAN_BREW+set}" ]]; then
    if [[ "$ATLASSIAN_BREW" != none && -x "$ATLASSIAN_BREW" ]]; then printf '%s\n' "$ATLASSIAN_BREW"; fi
    return 0
  fi
  [[ "$(bun_asset)" == bun-darwin-aarch64 ]] || return 0
  local candidate
  for candidate in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

# Bun's release asset for this Mac, as Bun's own installer chooses it: Apple silicon (also under Rosetta), else Intel
# with AVX2, else Intel's baseline build. ATLASSIAN_BUN_ARCH chooses it in tests.
bun_asset() {
  if [[ "${ATLASSIAN_INSTALLER_TEST:-}" == "1" && -n "${ATLASSIAN_BUN_ARCH:-}" ]]; then
    printf 'bun-darwin-%s\n' "$ATLASSIAN_BUN_ARCH"
    return 0
  fi
  if [[ "$(uname -m)" == arm64 || "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" == 1 ]]; then
    echo bun-darwin-aarch64
  elif sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -qw AVX2; then
    echo bun-darwin-x64
  else
    echo bun-darwin-x64-baseline
  fi
}

# How the installer would install Bun, in words for the question, --status and the help.
bun_install_how() {
  if [[ -n "$(find_brew)" ]]; then
    echo "with Homebrew (brew install bun)"
  else
    echo "Bun $BUN_VERSION from Bun's GitHub release, checked against its SHA-256, into ~/.bun/bin"
  fi
}

# Installs Bun (only after the person agreed, or --install-bun): with Homebrew if there is one (a failure stops,
# with no other route), else Bun's own release from GitHub at BUN_VERSION, checked against the pinned SHA-256 before
# anything is unpacked, into ~/.bun/bin. Never changes a shell profile and never replaces a Bun that is there.
install_bun() {
  local brew
  brew="$(find_brew)"
  if [[ -n "$brew" ]]; then
    print_step "Installing Bun with Homebrew (brew install bun)..."
    "$brew" install bun || {
      print_error "brew install bun failed (its output is above)"
      return 1
    }
    return 0
  fi
  local asset expected base url tmp actual listing bin="${HOME%/}/.bun/bin"
  asset="$(bun_asset)"
  case "$asset" in
    bun-darwin-aarch64) expected="$BUN_SHA256_AARCH64" ;;
    bun-darwin-x64) expected="$BUN_SHA256_X64" ;;
    bun-darwin-x64-baseline) expected="$BUN_SHA256_X64_BASELINE" ;;
    *)
      print_error "Bun has no release for this Mac ($asset)"
      return 1
      ;;
  esac
  base="https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION"
  if [[ "${ATLASSIAN_INSTALLER_TEST:-}" == "1" ]]; then
    [[ -z "${ATLASSIAN_BUN_BASE:-}" ]] || base="$ATLASSIAN_BUN_BASE"
    [[ -z "${ATLASSIAN_BUN_SHA256:-}" ]] || expected="$ATLASSIAN_BUN_SHA256"
  fi
  url="${base%/}/$asset.zip"
  if [[ -e "$bin/bun" || -L "$bin/bun" ]]; then
    print_error "$bin/bun is there already but isn't a usable Bun $BUN_MIN or later; leaving it alone (update it with: $bin/bun upgrade)"
    return 1
  fi
  print_step "Installing Bun $BUN_VERSION from Bun's GitHub release into ~/.bun/bin..."
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/atlassian-bun.XXXXXX")" || return 1
  if ! curl -fsSL --proto '=https,http' "$url" -o "$tmp/bun.zip"; then
    rm -rf "$tmp"
    print_error "Download failed: $url"
    return 1
  fi
  actual="$(shasum -a 256 <"$tmp/bun.zip" | awk '{ print $1 }')"
  if [[ "$actual" != "$expected" ]]; then
    rm -rf "$tmp"
    print_error "Bun's checksum doesn't match — Bun wasn't installed"
    print_error "Expected: $expected"
    print_error "Got:      $actual"
    return 1
  fi
  # The zip must hold the binary and its folder, and nothing else.
  listing="$(unzip -Z1 "$tmp/bun.zip" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
  if [[ "$listing" != "$asset/ $asset/bun " ]]; then
    rm -rf "$tmp"
    print_error "Bun's release doesn't hold just $asset/bun, so it wasn't installed"
    return 1
  fi
  if ! unzip -q -o "$tmp/bun.zip" "$asset/bun" -d "$tmp" 2>/dev/null || [[ -L "$tmp/$asset/bun" || ! -f "$tmp/$asset/bun" ]]; then
    rm -rf "$tmp"
    print_error "Couldn't unpack $asset/bun from Bun's release"
    return 1
  fi
  if ! { mkdir -p "$bin" && install -m 755 "$tmp/$asset/bun" "$bin/.bun.$$" && mv -f "$bin/.bun.$$" "$bin/bun"; }; then
    rm -rf "$tmp" "$bin/.bun.$$"
    print_error "Couldn't put Bun in $bin"
    return 1
  fi
  rm -rf "$tmp"
  print_success "Installed Bun $(bun_version "$bin/bun") in $bin (your shell profiles weren't changed; the entry finds it there)"
}

# Claude Desktop's config file followed through symbolic links, so it is changed where it really is and the link
# stays. $1 = the path Claude Desktop reads.
# Fails (printing nothing) for a loop or a chain of more than 20 links.
config_target() {
  local p="$1" t n=0
  while [[ -L "$p" ]]; do
    [[ "$n" -lt 20 ]] || return 1
    t="$(readlink "$p")" || return 1
    [[ "$t" == /* ]] || t="$(dirname "$p")/$t"
    p="$t"
    n=$((n + 1))
  done
  printf '%s\n' "$p"
}

# The version of the release an entry runs ($1 = <server folder>/current/manifest.json), or "none".
release_version() {
  osascript -l JavaScript - "$1" <<'JXA' 2>/dev/null || echo none
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(
    $(argv[0]).stringByResolvingSymlinksInPath,
    $.NSUTF8StringEncoding,
    null,
  );
  if (text.isNil()) return "none";
  try {
    const version = String(JSON.parse(text.js).version || "");
    return /^[0-9]+\.[0-9]+\.[0-9]+$/.test(version) ? version : "none";
  } catch (e) {
    return "none";
  }
}
JXA
}

# Reads or changes the entry in Claude Desktop's config file, with JavaScript for Automation (no jq, node or python),
# which keeps the keys' order and non-ASCII text.
#   entry_config state  <config> <launcher>
#     -> "missing" (no file), "invalid" (not a JSON object), "none" (no entry), "ours" (it runs <launcher>) or
#        "other" (it runs something else)
#   entry_config add    <config> <launcher> <bun folder> <out>
#   entry_config remove <config> <launcher> <out>
#     -> "changed" (the whole new file is written to <out>), "unchanged", "invalid", or for remove "other" (an
#        entry that runs something else is left alone). add keeps every other key; an entry that runs something
#        else is pointed at <launcher> and keeps its env (the person's settings).
entry_config() {
  osascript -l JavaScript - "$ENTRY_NAME" "$ENTRY_SYSTEM_PATH" "$@" <<'JXA' 2>/dev/null || echo error
ObjC.import("Foundation");
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
function run(argv) {
  const [name, systemPath, action, path, launcher] = argv;
  let config = {};
  if ($.NSFileManager.defaultManager.fileExistsAtPath(path)) {
    const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (text.isNil()) return "invalid";
    try {
      config = JSON.parse(text.js);
    } catch (e) {
      return "invalid";
    }
    if (!isObject(config)) return "invalid";
  } else if (action === "state") {
    return "missing";
  }
  if (config.mcpServers !== undefined && !isObject(config.mcpServers)) return "invalid";
  const servers = config.mcpServers || {};
  const entry = servers[name];
  const ours = isObject(entry) && entry.command === launcher;
  if (action === "state") return entry === undefined ? "none" : ours ? "ours" : "other";
  let out;
  if (action === "remove") {
    if (entry === undefined) return "unchanged";
    if (!ours) return "other";
    delete servers[name];
    out = argv[5];
  } else if (action === "add") {
    if (ours) return "unchanged";
    if (isObject(entry) && isObject(entry.env)) {
      // Only its env (the person's settings) is kept: keys of another kind of server (url, type) would mix.
      servers[name] = { command: launcher, args: [], env: entry.env };
    } else {
      const dirs = [argv[5], ...systemPath.split(":")];
      const env = { MCP_RUN_MODE: "config", PATH: dirs.filter((d, i) => d && dirs.indexOf(d) === i).join(":") };
      // A data folder other than the default goes with the entry, so the server finds its settings and releases.
      if (argv[7]) env.ATLASSIAN_MULTI_MCP_DATA_DIR = argv[7];
      servers[name] = { command: launcher, args: [], env };
    }
    config.mcpServers = servers;
    out = argv[6];
  } else {
    return "error";
  }
  const ok = $(JSON.stringify(config, null, 2) + "\n").writeToFileAtomicallyEncodingError(
    out,
    false,
    $.NSUTF8StringEncoding,
    null,
  );
  return ok ? "changed" : "error";
}
JXA
}

# Puts the checked new config ($2, a file) in place of Claude Desktop's ($1), after copying the old one to
# <config>.bak-<date and time>-<random> (a name mktemp reserves), keeping the old file's permissions. Prints the
# backup's path (nothing if there was no file).
replace_config() {
  local cfg="$1" new="$2" backup="" mode
  mkdir -p "$(dirname "$cfg")" || return 1
  if [[ -f "$cfg" ]]; then
    backup="$(mktemp "$cfg.bak-$(date '+%Y-%m-%dT%H%M%S')-XXXXXX")" || return 1
    cp -p "$cfg" "$backup" || return 1
    mode="$(stat -f '%Lp' "$cfg")" || return 1
    chmod "$mode" "$new" || return 1
  else
    chmod 600 "$new" || return 1
  fi
  mv -f "$new" "$cfg" || return 1
  printf '%s\n' "$backup"
}

# The entry as JSON, for adding it by hand. $1 = the launcher, $2 = Claude Desktop's config file, $3 = Bun's folder.
print_entry_by_hand() {
  local command path
  command="$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  path="$(printf '%s' "${3:+$3:}$ENTRY_SYSTEM_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  echo "To add it yourself: back up $2, put this inside its \"mcpServers\" object, then quit and reopen"
  echo "Claude Desktop:"
  echo ""
  echo "  \"$ENTRY_NAME\": {"
  echo "    \"command\": \"$command\","
  echo "    \"args\": [],"
  echo "    \"env\": { \"MCP_RUN_MODE\": \"config\", \"PATH\": \"$path\" }"
  echo "  }"
  echo ""
}

# What Claude Desktop says about the extension: "<enabled|disabled|blocked|unknown>", or "none" when it isn't
# installed. blocked: the organisation switched it off (orgBlockedReason; only its presence is read).
claude_extension_switch() {
  osascript -l JavaScript - "$1" <<'JXA' 2>/dev/null || echo unknown
ObjC.import("Foundation");
function read(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError($(path).stringByResolvingSymlinksInPath, $.NSUTF8StringEncoding, null);
  return text.isNil() ? undefined : JSON.parse(text.js);
}
function run(argv) {
  try {
    const all = (read(argv[0] + "/extensions-installations.json") || {}).extensions || {};
    const key = Object.keys(all).find((k) => /(^|\.)atlassian-mcp-server$/.test(k));
    if (!key || !/^[A-Za-z0-9._-]+$/.test(key)) return "none";
    const s = read(argv[0] + "/Claude Extensions Settings/" + key + ".json");
    if (!s) return "unknown";
    if (typeof s.orgBlockedReason === "string" && s.orgBlockedReason.trim()) return "blocked";
    return s.isEnabled === false ? "disabled" : s.isEnabled === true ? "enabled" : "unknown";
  } catch (e) {
    return "unknown";
  }
}
JXA
}

claude_running() { pgrep -x Claude >/dev/null 2>&1; }

# What Claude Desktop's log for the entry says about its server, from its last start on:
#   "<none|starting|running|stopped|failed> <UTC time> <error text, for failed>". $1 = the log file. Reads from the
# last start in the whole log: Desktop logs every message, so a busy server's start can be thousands of lines back.
server_state() {
  local from
  [[ -f "$1" && -r "$1" ]] || {
    echo none
    return 0
  }
  from="$(grep -a -n -E '^[0-9TZ:.-]+ \[[^]]*\] \[info\] Initializing server\.\.\.' "$1" 2>/dev/null | tail -n 1 | cut -d: -f1)"
  [[ -n "$from" ]] || {
    echo none
    return 0
  }
  # Only Claude Desktop's own words count: "<time> [<entry>] [<level>] <text>", matched at the start of <text>, so a
  # logged message whose content holds the same words changes nothing.
  tail -n "+$from" "$1" | LC_ALL=C tr -d '\000' | awk '
    match($0, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z \[[^]]*\] \[[a-z]+\] /) {
      ts = substr($0, 1, index($0, " ") - 2)
      text = substr($0, RLENGTH + 1)
      level = $0
      sub(/^[^]]*\] \[/, "", level)
      sub(/\].*$/, "", level)
      if (level == "info" && index(text, "Initializing server...") == 1) { state = "starting"; since = ts; err = ""; next }
      if (state == "") next
      if (index(text, "Server transport closed unexpectedly") == 1) { state = "failed"; since = ts; next }
      if (level == "error") {
        if (err == "") err = substr(text, 1, 140)
        if (index(text, "Server disconnected") == 1) { state = "failed"; since = ts }
        next
      }
      if (state == "failed") next
      if (index(text, "Server transport closed") == 1) { state = "stopped"; since = ts; next }
      if (state == "starting" && (index(text, "Server started and connected") == 1 || index(text, "Message from server:") == 1)) { state = "running"; since = ts }
    }
    END { if (state == "") print "none"; else print state, since, err }'
}

# A UTC time from the log ("2026-10-15T13:58:54.739") as local time: "14:58" today, "15 Oct 14:58" otherwise.
local_time() {
  local epoch
  epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${1%%.*}" '+%s' 2>/dev/null)" || {
    printf '%s UTC\n' "${1%%.*}"
    return 0
  }
  if [[ "$(date -r "$epoch" '+%Y-%m-%d')" == "$(date '+%Y-%m-%d')" ]]; then
    date -r "$epoch" '+%H:%M'
  else
    date -r "$epoch" '+%e %b %H:%M' | sed 's/^ //'
  fi
}

# When a file or link last changed, as a UTC time in Claude Desktop's log format, or nothing.
changed_at() {
  local epoch
  epoch="$(stat -f '%m' "$1" 2>/dev/null)" || return 0
  date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%S'
}

describe_server() {
  case "$1" in
    running) echo "running since $(local_time "$2")" ;;
    starting) echo "starting since $(local_time "$2")" ;;
    stopped) echo "stopped at $(local_time "$2")" ;;
    failed) echo "failed at $(local_time "$2")${3:+: $3}" ;;
    *) echo "hasn't started yet" ;;
  esac
}

# The entry's data folder when it isn't the default (it then goes into the entry's env), else nothing.
custom_entry_data_dir() {
  local d default
  d="$(entry_data_dir)"
  default="$(ATLASSIAN_MULTI_MCP_DATA_DIR='' entry_data_dir)"
  [[ "$d" == "$default" ]] || printf '%s\n' "$d"
}

# Paths Claude Desktop uses (tests point them elsewhere).
claude_config_path() { printf '%s\n' "${ATLASSIAN_CLAUDE_CONFIG:-$1/claude_desktop_config.json}"; }
entry_log_path() { printf '%s\n' "${ATLASSIAN_CLAUDE_LOGS:-${HOME%/}/Library/Logs/Claude}/mcp-server-$ENTRY_NAME.log"; }

# The entry's part of --status, ending with "Ready: yes" or one "Next:" line. $1 = Claude Desktop's support folder,
# $2 = the latest version (or "unknown"), $3 = the --entry command, $4 = the extension's version or "none".
print_entry_status() {
  local claude_support="$1" latest="$2" entry_cmd="$3" ext_version="$4"
  local server_dir release cfg cfg_state e_srv e_since e_err switched stale=false entry_used=false open=false
  local switch bun bun_v
  switch="$(claude_extension_switch "$claude_support")"
  echo "claude_extension_state: $switch"
  server_dir="$(entry_data_dir)/server"
  release="$(release_version "$server_dir/current/manifest.json")"
  cfg="$(config_target "$(claude_config_path "$claude_support")")" || cfg=""
  if [[ -n "$cfg" ]]; then cfg_state="$(entry_config state "$cfg" "$server_dir/$LAUNCHER_NAME")"; else cfg_state=invalid; fi
  read -r e_srv e_since e_err <<<"$(server_state "$(entry_log_path)")"
  switched="$(changed_at "$server_dir/current")"
  if [[ "$e_srv" == running && -n "$switched" && "$e_since" < "$switched" ]]; then stale=true; fi
  if [[ "$release" != none || "$cfg_state" == ours || "$cfg_state" == other ]]; then entry_used=true; fi
  claude_running && open=true
  bun="$(find_bun)"
  if [[ -n "$bun" ]]; then
    bun_v="$(bun_version "$bun")"
    echo "bun: $bun ($bun_v)"
  else
    echo "bun: not installed (only the mcpServers entry needs it; --entry offers to install it $(bun_install_how))"
  fi
  local where
  case "$cfg_state" in
    ours) where="in Claude Desktop's config as $ENTRY_NAME" ;;
    other) where="Claude Desktop's $ENTRY_NAME entry runs something else" ;;
    invalid | error) where="Claude Desktop's config can't be read as JSON" ;;
    *) where="not in Claude Desktop's config" ;;
  esac
  echo "entry: $([[ "$release" == none ]] && echo "no release installed" || echo "release $release"), $where"
  if [[ "$entry_used" == true ]]; then
    if [[ "$open" == true ]]; then
      echo "entry_server: $(describe_server "$e_srv" "$e_since" "$e_err")"
    else
      echo "entry_server: not running (Claude Desktop isn't open)"
    fi
  fi

  local next=""
  if [[ "$entry_used" == true ]]; then
    if [[ -z "$bun" ]] || ! version_at_least "${bun_v:-0}" "$BUN_MIN"; then
      next="install Bun $BUN_MIN or later, which the $ENTRY_NAME entry runs with (ask first): $entry_cmd --install-bun"
    elif [[ "$release" == none ]]; then
      next="install the release for the $ENTRY_NAME entry: $entry_cmd"
    elif [[ "$cfg_state" == invalid || "$cfg_state" == error ]]; then
      next="Claude Desktop's claude_desktop_config.json can't be read as JSON: fix it, then run $entry_cmd"
    elif [[ "$cfg_state" != ours ]]; then
      next="add the $ENTRY_NAME entry to Claude Desktop's config: $entry_cmd"
    elif [[ "$switch" == enabled ]]; then
      next="switch the extension off (Settings > Extensions > Atlassian MCP Server): with the entry on too, Claude sees every tool twice."
    elif [[ "$open" != true ]]; then
      next="open Claude Desktop."
    elif [[ "$e_srv" == failed ]]; then
      next="quit and reopen Claude Desktop; if it still fails, see ~/Library/Logs/Claude/mcp-server-$ENTRY_NAME.log."
    elif [[ "$e_srv" == none || "$e_srv" == stopped ]]; then
      next="quit Claude Desktop (⌘Q) and open it again, so it starts the $ENTRY_NAME entry."
    elif [[ "$e_srv" == running && "$stale" == true ]]; then
      next="quit Claude Desktop (⌘Q) and open it again, so it starts release $release."
    elif [[ "$e_srv" != running ]]; then
      next="wait a minute and check again: Claude Desktop is starting the $ENTRY_NAME entry."
    fi
  elif [[ "$switch" == blocked ]]; then
    next="your organisation blocks the extension: install it as an mcpServers entry instead: $entry_cmd"
  elif [[ "$ext_version" == none ]]; then
    next="run the install command, then click Install in Claude Desktop."
  elif [[ "$switch" == disabled ]]; then
    next="switch the extension on in Claude Desktop: Settings > Extensions > Atlassian MCP Server."
  elif [[ "$open" != true ]]; then
    next="open Claude Desktop."
  fi
  if [[ "$latest" != unknown ]]; then
    if [[ "$entry_used" == true && "$latest" == *-* ]]; then
      echo "update: the latest here is a pre-release; the mcpServers entry installs only stable releases"
    elif [[ "$entry_used" == true ]] && { [[ "$release" == none ]] || version_older "$release" "$latest"; }; then
      echo "update: $latest is available (Update now on the update card in Claude, or run the --entry command again)"
    elif [[ "$entry_used" != true && "$ext_version" != none ]] && version_older "$ext_version" "$latest"; then
      echo "update: $latest is available (run the install command again)"
    fi
  fi
  if [[ -n "$next" ]]; then echo "Next: $next"; else echo "Ready: yes"; fi
}

# --entry, once the release is downloaded and checked ($1/latest.mcpb): installs it with the release's own
# install-release, adds the entry to Claude Desktop's config (if $5 = true, the person's go-ahead), and waits for
# Claude Desktop to start it (up to $6 seconds). $2 = version, $3 = Bun, $4 = Claude Desktop's support folder.
install_entry() {
  local dir="$1" version="$2" bun="$3" claude_support="$4" consent="$5" wait_secs="$6" status_cmd="$7"
  local claude_app="$8"
  local cfg entry_log server_dir before_release release launcher out
  cfg="$(config_target "$(claude_config_path "$claude_support")")" || die "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
  entry_log="$(entry_log_path)"
  server_dir="$(entry_data_dir)/server"
  before_release="$(release_version "$server_dir/current/manifest.json")"

  local intact=false
  if [[ -x "$server_dir/$LAUNCHER_NAME" && -f "$server_dir/current/dist/index.js" && -f "$server_dir/current/dist/install-release.js" ]]; then
    intact=true
  fi
  if [[ -n "$version" && "$before_release" == "$version" && "$intact" == true ]]; then
    launcher="$server_dir/$LAUNCHER_NAME"
    print_success "Release $version is already installed in $server_dir"
  elif [[ -n "$version" && "$before_release" != none && "$intact" == true ]] && version_older "$version" "$before_release"; then
    # Never a silent downgrade: the entry keeps the newer release it has (Update now may have installed it).
    launcher="$server_dir/$LAUNCHER_NAME"
    print_warning "Release $before_release is installed, newer than the site's $version; keeping it."
  else
    print_step "Installing the release for the $ENTRY_NAME entry..."
    local stage="$ATLASSIAN_TEMP_DIR/release"
    mkdir -p "$stage"
    unzip -q -o "$dir/latest.mcpb" -d "$stage" >/dev/null 2>&1 || die "Couldn't unpack $dir/latest.mcpb"
    [[ -f "$stage/dist/install-release.js" ]] || die "$dir/latest.mcpb is a release from before the mcpServers entry; nothing was changed"
    # The release installs itself (src/install-release.ts): it checks the bundle again, unpacks it beside the version
    # in use and switches to it. Claude Desktop's config isn't touched yet.
    if ! out="$(cd "$stage" && ATLASSIAN_MULTI_MCP_DATA_DIR="$(entry_data_dir)" "$bun" --no-env-file \
      "$stage/dist/install-release.js" --bundle "$dir/latest.mcpb" 2>&1)"; then
      print_error "Installing the release failed, so Claude Desktop's config wasn't changed:"
      printf '%s\n' "$out" | tail -n 15 >&2
      exit 1
    fi
    launcher="$(printf '%s\n' "$out" | sed -n 's/^Claude Desktop entry command: //p' | tail -n 1)"
    [[ -n "$launcher" && -x "$launcher" ]] || die "The release installed, but didn't say where its command is"
    server_dir="${launcher%/*}"
  fi
  release="$(release_version "$server_dir/current/manifest.json")"
  if [[ "$before_release" != none && "$before_release" != "$release" ]]; then
    print_success "Installed release $release (was $before_release) in $server_dir"
  elif [[ "$before_release" == none ]]; then
    print_success "Installed release $release in $server_dir"
  fi

  local cfg_state changed=false
  cfg_state="$(entry_config state "$cfg" "$launcher")"
  case "$cfg_state" in
    ours)
      print_success "Claude Desktop's config already has the $ENTRY_NAME entry"
      ;;
    none | missing | other)
      if [[ "$consent" != true ]]; then
        print_warning "Claude Desktop's config wasn't changed, as you chose."
        print_entry_by_hand "$launcher" "$cfg" "${bun%/*}"
        return 0
      fi
      local new result backup
      new="$(mktemp "$ATLASSIAN_TEMP_DIR/config.XXXXXX")" || die "Couldn't create a temporary file"
      result="$(entry_config add "$cfg" "$launcher" "${bun%/*}" "$new" "$(custom_entry_data_dir)")"
      [[ "$result" == changed && "$(entry_config state "$new" "$launcher")" == ours ]] ||
        die "Couldn't prepare the new config ($result); $cfg wasn't changed"
      backup="$(replace_config "$cfg" "$new")" || die "Couldn't write $cfg"
      changed=true
      if [[ "$cfg_state" == other ]]; then
        print_success "Pointed Claude Desktop's $ENTRY_NAME entry at release $release${backup:+ (backup: $backup)}"
      else
        print_success "Added the $ENTRY_NAME entry to Claude Desktop's config${backup:+ (backup: $backup)}"
      fi
      ;;
    *)
      print_error "Claude Desktop's config can't be read as JSON, so it was left alone: $cfg"
      print_entry_by_hand "$launcher" "$cfg" "${bun%/*}" >&2
      exit 1
      ;;
  esac

  if [[ "$(claude_extension_switch "$claude_support")" == enabled ]]; then
    print_warning "The Atlassian MCP Server extension is switched on too, so Claude would see every tool twice."
    echo "  Switch it off in Claude Desktop: Settings > Extensions > Atlassian MCP Server."
  fi

  # Claude Desktop reads its config when it starts: wait for a start of the entry from now on (or, when nothing
  # changed, one that runs this release already).
  local start_ts already=false srv since err switched
  start_ts="$(date -u '+%Y-%m-%dT%H:%M:%S')"
  read -r srv since err <<<"$(server_state "$entry_log")"
  switched="$(changed_at "$server_dir/current")"
  if [[ "$changed" != true && "$srv" == running && -n "$switched" && ! "$since" < "$switched" ]] && claude_running; then
    already=true
  fi
  if [[ "$already" != true ]]; then
    echo ""
    if claude_running; then
      echo "In Claude Desktop: quit it (Claude > Quit Claude, or ⌘Q) and open it again, so it starts the"
      echo "$ENTRY_NAME entry."
    elif [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" == "1" ]]; then
      print_step "Would open: open -a $(printf '%q' "$claude_app")"
    else
      print_step "Opening Claude Desktop..."
      open -a "$claude_app" || print_warning "Couldn't open Claude Desktop. Open it yourself."
    fi
    echo ""
  fi
  local ready=false waited=0
  while [[ "$already" != true ]]; do
    read -r srv since err <<<"$(server_state "$entry_log")"
    if [[ "$srv" == running && ! "$since" < "$start_ts" ]]; then
      ready=true
      break
    fi
    if [[ "$srv" == failed && ! "$since" < "$start_ts" ]]; then break; fi
    [[ "$waited" -lt "$wait_secs" ]] || break
    [[ "$waited" -ne 0 ]] || print_step "Waiting for Claude Desktop to start the $ENTRY_NAME entry (up to $((wait_secs / 60)) minutes)..."
    touch "$ATLASSIAN_TEMP_DIR" 2>/dev/null || true
    sleep 2
    waited=$((waited + 2))
  done

  echo ""
  if [[ "$already" == true ]]; then
    print_success "Already up to date and running: the $ENTRY_NAME entry, release $release"
  elif [[ "$ready" == true ]]; then
    print_success "Installed and running: the $ENTRY_NAME entry, release $release"
  elif [[ "$srv" == failed && ! "$since" < "$start_ts" ]]; then
    print_error "Claude Desktop started the $ENTRY_NAME entry, but it failed${err:+: $err}"
    print_error "Quit and reopen Claude Desktop; if it still fails, see ~/Library/Logs/Claude/mcp-server-$ENTRY_NAME.log."
    exit 1
  elif [[ "$wait_secs" -eq 0 ]]; then
    print_success "Done. Quit Claude Desktop (⌘Q) and open it again if it was open, so it starts the $ENTRY_NAME"
    echo "entry, then start a new chat."
  else
    print_error "Claude Desktop hasn't started the $ENTRY_NAME entry within $((wait_secs / 60)) minutes."
    print_error "Quit Claude Desktop (⌘Q) and open it again, then check with the --status command below."
    echo "Check the install any time with:"
    echo "  $status_cmd"
    exit 1
  fi
  echo ""
  echo "Next, in a new chat in Claude Desktop:"
  echo "  1. Ask \"Is Atlassian connected?\" (it runs atlassian_ensure_ready and tells you the next step)."
  echo "  2. Write tools are off: Claude can only read and search. To let it create and change things, ask Claude to"
  echo "     \"show my Atlassian settings\", turn on Enable write tools on the card, then quit and reopen Claude Desktop."
  echo ""
  echo "Check the install any time with:"
  echo "  $status_cmd"
}

# --entry --uninstall: removes the entry from Claude Desktop's config (only one that runs the installed release; a
# backup is kept) and the installed release. Settings, sites and tokens are kept.
uninstall_entry() {
  local claude_support="$1" yes="$2"
  local cfg server_dir launcher cfg_state has_release=false
  cfg="$(config_target "$(claude_config_path "$claude_support")")" || die "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
  server_dir="$(entry_data_dir)/server"
  launcher="$server_dir/$LAUNCHER_NAME"
  cfg_state="$(entry_config state "$cfg" "$launcher")"
  if [[ -f "$launcher" && -d "$server_dir/versions" ]]; then has_release=true; fi
  if [[ "$cfg_state" == invalid || "$cfg_state" == error ]]; then
    die "Claude Desktop's config can't be read as JSON, so nothing was changed: $cfg. Fix it, then run this again"
  fi
  if [[ "$cfg_state" != ours && "$has_release" != true ]]; then
    [[ "$cfg_state" != other ]] || print_warning "Claude Desktop's $ENTRY_NAME entry runs something else; leaving it alone."
    die "Nothing to remove: no $ENTRY_NAME entry from this installer and no release in $server_dir"
  fi
  local what=()
  [[ "$cfg_state" != ours ]] || what+=("the $ENTRY_NAME entry in Claude Desktop's config (a backup is kept)")
  [[ "$has_release" != true ]] || what+=("the installed release in $server_dir")
  local question
  question="Remove $(printf '%s and ' "${what[@]}")"
  question="${question% and }?"
  if [[ "$yes" != true ]] && ! ask_yes_no "$question"; then
    die "Not removed (with no terminal, add --yes)"
  fi
  if [[ "$cfg_state" == ours ]]; then
    ATLASSIAN_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atlassian-entry.XXXXXX")" || die "Couldn't create a temporary folder"
    trap cleanup_temp EXIT
    local new result backup
    new="$ATLASSIAN_TEMP_DIR/config.json"
    result="$(entry_config remove "$cfg" "$launcher" "$new")"
    [[ "$result" == changed && "$(entry_config state "$new" "$launcher")" == none ]] ||
      die "Couldn't prepare the new config ($result); $cfg wasn't changed"
    backup="$(replace_config "$cfg" "$new")" || die "Couldn't write $cfg"
    print_success "Removed the $ENTRY_NAME entry from Claude Desktop's config${backup:+ (backup: $backup)}"
  elif [[ "$cfg_state" == other ]]; then
    print_warning "Claude Desktop's $ENTRY_NAME entry runs something else; left it alone."
  fi
  if [[ "$has_release" == true ]]; then
    rm -rf "${server_dir:?}"
    print_success "Removed $server_dir"
  fi
  echo "Quit Claude Desktop and open it again. Kept: your sites and saved tokens (the installer's --uninstall without"
  echo "--entry removes those) and the entry's folder $(entry_data_dir) with its settings (delete it yourself)."
}

main() {
  [[ -n "${HOME:-}" ]] || die "HOME isn't set, so the installer can't find your home folder"
  local data_dir="" force_token=false status_only=false no_wait=false uninstall=false yes=false site_args=()
  local entry=false install_bun_ok=false
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
      --entry)
        entry=true
        shift
        ;;
      --install-bun)
        install_bun_ok=true
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

  if [[ "$install_bun_ok" == true && ("$entry" != true || "$uninstall" == true || "$status_only" == true) ]]; then
    die "--install-bun goes with --entry: the mcpServers entry is what needs Bun"
  fi

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
  local entry_cmd="curl -fsSL $q_base/install.sh | bash -s -- --entry"
  if [[ "$is_default" != true ]]; then
    status_cmd+=" --dir $q_dir"
    entry_cmd+=" --dir $q_dir"
  fi

  if [[ "$status_only" == true ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
    print_status "$data_dir" "$claude_support" "$sites"
    local latest
    latest="$(curl -fsSL --max-time 15 "$install_base/latest.version" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || latest=unknown
    echo "latest: $latest"
    print_entry_status "$claude_support" "$latest" "$entry_cmd" \
      "$(claude_extension_version "$claude_support/extensions-installations.json")"
    return 0
  fi

  if [[ "$uninstall" == true && "$entry" == true ]]; then
    [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
    uninstall_entry "$claude_support" "$yes"
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
  if [[ "$entry" == true ]]; then
    print_step "Installing it as a Claude Desktop mcpServers entry ($ENTRY_NAME). It never quits Claude Desktop."
  else
    print_warning "This installer may need to quit and reopen Claude Desktop (only after an update). It asks first."
  fi
  echo ""

  print_step "Checking prerequisites..."
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS"
  [[ -d "$claude_app" ]] || die "Claude.app not found at: $claude_app (install Claude Desktop first)"
  local tool
  for tool in curl shasum osascript open security awk sed; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not available"
  done
  if [[ "$entry" == true ]]; then
    command -v unzip >/dev/null 2>&1 || die "unzip is not available"
  fi
  print_success "macOS and Claude Desktop found"

  # --entry: every check and question comes first, before anything is downloaded or installed.
  local bun="" need_bun=false cfg_consent=false
  if [[ "$entry" == true ]]; then
    # The entry installs only stable releases (src/install-release.ts); the pre-release site serves others.
    local site_version
    site_version="$(curl -fsSL --max-time 15 "$install_base/latest.version" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$site_version" == *-* ]]; then
      die "This site serves a pre-release ($site_version), and the $ENTRY_NAME entry installs only stable releases. Nothing was changed. Use the stable site: curl -fsSL $SITE_BASE_DEFAULT/install.sh | bash -s -- --entry"
    fi
    # Bun: the entry runs with it. Installing software is the person's call: a question in a terminal, else
    # --install-bun (their go-ahead). It is installed only once the download has been checked, below.
    bun="$(find_bun)"
    if [[ -n "$bun" ]] && ! version_at_least "$(bun_version "$bun")" "$BUN_MIN"; then
      die "Bun $(bun_version "$bun") at $bun is older than $BUN_MIN, which the $ENTRY_NAME entry needs. Nothing was changed. Update it (brew upgrade bun, or $bun upgrade), then run this again"
    fi
    if [[ -z "$bun" ]]; then
      local how
      how="$(bun_install_how)"
      print_warning "Bun isn't installed, and the $ENTRY_NAME entry runs with it."
      if [[ "$install_bun_ok" == true ]] || ask_yes_no "Install Bun now, $how?"; then
        need_bun=true
      elif can_answer; then
        die "Bun wasn't installed, so nothing was changed. Install it yourself (brew install bun, or see https://bun.sh), then run this again"
      else
        die "Nothing was changed. With the user's go-ahead, run this again with --install-bun to install Bun $how; or install it yourself (brew install bun)"
      fi
    else
      print_success "Bun $(bun_version "$bun"): $bun"
    fi
    # Claude Desktop's config: the person's go-ahead to change it, now rather than after the download.
    local cfg_path pre_state question
    cfg_path="$(config_target "$(claude_config_path "$claude_support")")" || die "Claude Desktop's config is a symbolic link that never ends (a loop, or more than 20 links), so nothing was changed"
    pre_state="$(entry_config state "$cfg_path" "$(entry_data_dir)/server/$LAUNCHER_NAME")"
    case "$pre_state" in
      ours) cfg_consent=true ;;
      none | missing | other)
        if [[ "$pre_state" == other ]]; then
          question="Claude Desktop's $ENTRY_NAME entry runs something else. Point it at this release ($cfg_path; a backup is kept)?"
        else
          question="Add the $ENTRY_NAME entry to Claude Desktop's config ($cfg_path; a backup is kept)?"
        fi
        if [[ "$yes" == true ]] || ask_yes_no "$question"; then
          cfg_consent=true
        elif ! can_answer; then
          die "Nothing was changed. With the user's go-ahead to change Claude Desktop's config, run this again with --yes"
        fi
        ;;
      *)
        die "Claude Desktop's config can't be read as JSON, so nothing was changed: $cfg_path. Fix it (Claude Desktop needs valid JSON too), then run this again"
        ;;
    esac
  fi

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

  if [[ "$entry" == true ]]; then
    if [[ "$version" == *-* ]]; then
      die "This site serves a pre-release ($version), and the $ENTRY_NAME entry installs only stable releases. The verified download is kept in $data_dir; nothing else was changed"
    fi
    # Before anything is installed (Bun included): the release must be able to install itself as the entry.
    # (grep without -q reads the whole list, so unzip never dies of a closed pipe under pipefail)
    unzip -Z1 "$data_dir/latest.mcpb" 2>/dev/null | grep -x 'dist/install-release.js' >/dev/null ||
      die "The site's release ($version) is from before the mcpServers entry, so it can't be installed as one. The verified download is kept in $data_dir; nothing else was changed"
    if [[ "$need_bun" == true ]]; then
      install_bun || die "Bun wasn't installed, so the entry wasn't set up (only the verified download is kept, in $data_dir). Install Bun yourself (brew install bun, or see https://bun.sh), then run this again"
      bun="$(find_bun)"
      [[ -n "$bun" ]] || die "Bun was installed, but the installer can't find it (looked in your PATH, /opt/homebrew/bin, /usr/local/bin and ~/.bun/bin)"
      version_at_least "$(bun_version "$bun")" "$BUN_MIN" || die "The Bun at $bun is older than $BUN_MIN"
      print_success "Bun $(bun_version "$bun"): $bun"
    fi
    local entry_wait="${ATLASSIAN_INSTALL_WAIT_SECS:-}"
    if [[ -z "$entry_wait" ]]; then
      if [[ "${ATLASSIAN_INSTALL_NO_OPEN:-}" == "1" ]]; then entry_wait=0; else entry_wait=600; fi
    fi
    [[ "$entry_wait" =~ ^[0-9]+$ ]] || entry_wait=600
    if [[ "$no_wait" == true ]]; then entry_wait=0; fi
    install_entry "$data_dir" "$version" "$bun" "$claude_support" "$cfg_consent" "$entry_wait" "$status_cmd" "$claude_app"
    return 0
  fi

  local ext_file="$claude_support/extensions-installations.json"
  local before
  before="$(claude_extension_version "$ext_file")"

  # Installing the extension again doesn't help when the organisation blocks it: say what does.
  if [[ "$(claude_extension_switch "$claude_support")" == blocked ]]; then
    print_error "Claude Desktop has the Atlassian MCP Server extension, but your organisation blocks it."
    echo "  Install the same release as a Claude Desktop mcpServers entry instead:" >&2
    echo "    $entry_cmd" >&2
    exit 1
  fi

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
    echo "  Write tools are off by default: Claude can then only read and search. To let it create and change"
    echo "  things too, turn on \"Enable write tools\" there (or later in Settings > Extensions)."
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
  # Claude Desktop installed it, but the organisation switched it off: say what works instead.
  if [[ "$installed" != none && "$(claude_extension_switch "$claude_support")" == blocked ]]; then
    print_error "Claude Desktop installed the Atlassian MCP Server extension, but your organisation blocks it."
    echo "  Install the same release as a Claude Desktop mcpServers entry instead:" >&2
    echo "    $entry_cmd" >&2
    exit 1
  fi
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
  echo "  3. To let Claude create and change things, turn on \"Enable write tools\": Claude Desktop > Settings > Extensions >"
  echo "     Atlassian MCP Server > Configure. Until then it can only read and search."
  if [[ "$is_default" == true ]]; then
    echo "To check the state: run the same command with --status. To update later, run the same command again."
  else
    printf 'To check the state: run the same command with --status (keep --dir %s). To update, run it again with --dir %s\n' "$q_dir" "$q_dir"
  fi
  echo ""
}

main "$@"
