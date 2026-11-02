# Atlassian MCP Server

**Give Claude every Jira, Confluence and Rovo API. It runs locally on your Mac, signs in as you on each of your Atlassian sites, and can only do what your account can.**

Version **1.2.1** · macOS · Claude Desktop extension

- [Install: for people](#install-for-people)
- [Install: for AI agents](#install-for-ai-agents)
- [What you can do](#what-you-can-do)
- [API tokens](#api-tokens)
- [Updates](#updates)
- [Tools](#tools)
- [Security and privacy](#security-and-privacy)
- [Troubleshooting](#troubleshooting)

---

## Install: for people

Open Terminal and run:

```bash
curl -fsSL https://wpp-jamie-mills.github.io/atlassian-mcp-server-site/install.sh | bash
```

Then:

1. For each site, enter your Atlassian email and paste an API token into the secure prompt (it goes straight to your macOS Keychain), then click Install in the dialog Claude Desktop opens.
2. Ask Claude: "Is Atlassian connected?" It runs `atlassian_ensure_ready`, which checks each site and tells you the one next step.
3. For Rovo search and the Teamwork Graph, ask Claude to sign in to Rovo for each site. It opens the Atlassian sign-in page in your browser, once per site.

You need macOS, Claude Desktop and a token for each site: an Atlassian API token, or a Jira personal access token for a self-hosted Jira Data Center. From version 1.1.0, Claude offers each new version in the chat; running the same command again also updates it.

## Install: for AI agents

Use these steps if you are an AI agent installing this for a user.

1. **Check the machine.** Continue only if `uname -s` prints `Darwin` and `/Applications/Claude.app` exists. Otherwise tell the user it needs macOS with Claude Desktop installed.
2. **Run the installer** with this one command. It downloads the extension, checks its SHA-256 (nothing is installed before the check passes) and opens Claude Desktop's install dialog. `ATLASSIAN_INSTALL_TTY=/dev/null` means there is no terminal: it never quits or restarts an app, answers no to every question and never opens the token prompt. `--no-wait` makes it exit 0 once the dialog is open. It exits non-zero, with the reason on stderr, if anything fails before then. To choose the sites, add `--site <site>` once per site (e.g. `--site acme.atlassian.net`).

```bash
curl -fsSL https://wpp-jamie-mills.github.io/atlassian-mcp-server-site/install.sh | ATLASSIAN_INSTALL_TTY=/dev/null bash -s -- --no-wait
```

3. **Hand over to the user.** Ask them to click **Install** in Claude Desktop. For each site without a token, call `atlassian_set_token` with the site: a secure prompt on their Mac (for a Jira Data Center site, given by its full host, it asks for a personal access token). Never ask for the token in chat.
4. **Verify.** Run the installer again with `--status` (after `bash -s --`), or call `atlassian_ensure_ready` in Claude Desktop: it reports each site and the single next step.
5. **Rovo (optional).** Call `atlassian_rovo_sign_in` with each site; the user approves access in their browser once per site.

## What you can do

**Every Jira and Confluence REST API.** All 1,191 operations Atlassian publishes: Jira (629), Jira Software boards, sprints, epics and backlogs (105), Jira Service Management (75), and Confluence v2 (252) and v1 (130). Claude finds the operation it needs with `atlassian_discover` and runs it, so nothing is out of reach, from workflows and permission schemes to page restrictions and customer requests.

**Everyday work in Markdown.** Search with JQL or CQL, read, create, edit, move and comment on issues, and read, create, update and comment on pages and blog posts. Claude writes Markdown; the server converts it to Atlassian's format and back.

**Service desk tickets.** Raise a request on any Jira Service Management portal you can use, the way the portal's form would: Claude finds the portal and request type, reads the form (required fields, choices) and fills it in. It works on Jira Cloud and on self-hosted Jira Data Center, and lists the requests you've raised with their status.

**Find my ticket.** Ask for your ticket about something and Claude searches every site you've set up: the requests you raised on (or were added to) a service desk portal and, on Cloud, the Jira issues you reported, are assigned or watch. It matches the request type and portal as well as the summary, so "my Delphi ticket" finds a *Delphi Access Request* whatever its summary says, even in a service desk where you're only a customer and Jira search can't see it. The answer ends with what each site gave (searched, failed or timed out), so "nothing found" never hides a site that wasn't read.

**Atlassian GraphQL.** Queries and mutations against the platform graph behind Jira, Confluence, Goals, Projects and Teams.

**Rovo.** Rovo search across Jira, Confluence and the apps your organisation connected, and the Teamwork Graph: everything linked to an issue, page, person or goal in one call. Atlassian offers these only through its hosted Rovo MCP server, so this server signs in to it for you.

**Several sites at once.** Each site has its own credentials (an email and API token, or a personal access token for Data Center), so sites can use different accounts. Choose them with the installer's `--site`, or add one any time with `atlassian_set_token`.

**Jira Data Center too.** A self-hosted Jira (such as `jira.example.com`) is recognised when you add it with `atlassian_set_token`, which then asks for a Jira personal access token. On Data Center the service desk tools, the Jira Software and Jira Service Management catalog operations and `atlassian_request` (with `/rest/api/2/` paths) work; the other Jira and Confluence tools, GraphQL and Rovo need Atlassian Cloud.

Example prompts:

```
"Is Atlassian connected?"
"Show my open issues in ENG on acme, newest first"
"Move ENG-1423 to In Review and comment that the PR is up"
"Summarise the Q3 planning page in the DATA space on our other site"
"Create a page under 'Runbooks' with these steps"
"List the sprints on the Platform board and what's left in the active one"
"What's linked to ENG-1423: PRs, builds, pages, people?"
"Find what we decided about data retention" (Rovo search)
"Raise a ticket on the Data & Tech portal: my VPN drops every hour"
"What's the status of my open service desk requests on jira.example.com?"
"Find my ticket about Delphi access"
```

## API tokens

Create a token at https://id.atlassian.com/manage-profile/security/api-tokens and give it to the installer or `atlassian_set_token`, never to Claude in chat. A classic token can do whatever your account can. A scoped token can do only what its scopes allow; the server notices and sends its requests through `api.atlassian.com`, which scoped tokens need. Each site keeps its own email and token, so a site where you use a different Atlassian account just gets a different token. Some organisations block API tokens for managed accounts; if Atlassian rejects a token you know is right, ask your Atlassian admin.

A Jira Data Center site doesn't use Atlassian accounts or API tokens. Create a personal access token in that Jira instead (profile picture → Profile → Personal Access Tokens → Create token) and paste it into the prompt `atlassian_set_token` opens. Your Jira administrator decides whether personal access tokens are allowed.

Rovo doesn't use the API token: Atlassian only allows a browser sign-in (OAuth) for its Rovo MCP server. Atlassian's consent page grants one site at a time, so sign in once for each site you want Rovo on.

## Updates

From version 1.1.0, the Claude Desktop extension checks its landing page for a newer version once a day (the **Check for updates** setting, on by default). When there is one, Claude shows a card in the chat with **Update now** and **Not now**. Update now downloads the new version, checks its SHA-256 and that it really is this extension at that version, and opens Claude Desktop's install dialog. Nothing installs until you click Install there, and your tokens, sites and sign-ins are kept. Not now hides that version for a week. You can also ask Claude "Is there an update to the Atlassian extension?", or run the install command again.

## Tools

### Setup

| Tool | What it does |
|---|---|
| `atlassian_ensure_ready` | Report, for each Atlassian site, whether an API token is saved and works for Jira and Confluence, whether Rovo is signed in, and the single next step. |
| `atlassian_set_token` | Open a native macOS prompt where the user enters their Atlassian account email and pastes an API token for one site. |

### Jira

| Tool | What it does |
|---|---|
| `atlassian_jira_search` | Search Jira issues with JQL, e.g. `project = ENG AND status != Done ORDER BY updated DESC` or `assignee = currentUser() AND resolution = Unresolved`. |
| `atlassian_jira_get_issue` | Read one Jira issue in full: summary, status, people, dates, every non-empty field (custom fields by name), description and latest comments as Markdown, subtasks, links and attachments. |
| `atlassian_jira_create_issue` | Create a Jira issue (task, bug, story, epic, subtask…). |
| `atlassian_jira_edit_issue` | Change fields on a Jira issue: summary, description (Markdown), assignee, priority, labels (replace, add or remove), components, parent, due date, or any field in Jira's REST form. |
| `atlassian_jira_transition_issue` | Change a Jira issue's status by applying a workflow transition, by transition name, target status name or id. |
| `atlassian_jira_add_comment` | Add a comment (Markdown) to a Jira issue, visible to everyone who can see it unless visibility restricts it. |
| `atlassian_jira_list_projects` | List the Jira projects the account can see, optionally filtered by name or key, with their keys and leads. |

### Confluence

| Tool | What it does |
|---|---|
| `atlassian_confluence_search` | Search Confluence with CQL, e.g. `type = page AND space = ENG AND text ~ "release plan" ORDER BY lastmodified DESC`, or pass text for a simple full-text search. |
| `atlassian_confluence_get_page` | Read a Confluence page or blog post: title, space, version, dates, link and the body as Markdown. format 'storage' returns Confluence's XHTML storage format and 'adf' the raw document, e.g. to see macros exactly. |
| `atlassian_confluence_create_page` | Create a Confluence page (or blog post) from Markdown in a space, optionally under a parent page. |
| `atlassian_confluence_update_page` | Update a Confluence page or blog post: new title and/or body from Markdown, replacing the body or appending to it. |
| `atlassian_confluence_add_comment` | Add a footer comment (Markdown) to a Confluence page or blog post, or reply to an existing comment. |
| `atlassian_confluence_list_spaces` | List the Confluence spaces the account can see, with keys, ids, names and types. |

### Service desk

| Tool | What it does |
|---|---|
| `atlassian_find_my_tickets` | Find the user's own tickets on every set-up Atlassian site: the requests they raised on (or were added to) a service desk portal, and on Cloud the Jira issues they reported, are assigned or watch. |
| `atlassian_service_desk_list_portals` | List the Jira Service Management portals (service desks) the account can raise requests on, with each portal's id, name, project key and link. |
| `atlassian_service_desk_list_request_types` | List the request types on a Jira Service Management portal (what the portal offers to raise, such as 'Get IT help' or 'Request access'), grouped as the portal groups them, with ids, descriptions and create links. |
| `atlassian_service_desk_get_request_form` | Read the form of a portal request type: every field with its id, whether it's required, what it takes and its choices, plus whether the account can raise it for someone else or share it. |
| `atlassian_service_desk_create_request` | Raise a request (ticket) on a Jira Service Management portal, as the portal's form would, on Jira Cloud or Jira Data Center. |
| `atlassian_service_desk_list_requests` | List the service desk requests the account raised or was added to, newest first, with status, request type, portal and link; open ones by default. |

### Every REST API, and GraphQL

| Tool | What it does |
|---|---|
| `atlassian_discover` | Search the catalog of Jira and Confluence REST operations: 1,191 operations from the Jira platform, Jira Software (boards, sprints, epics, backlog), Jira Service Management and Confluence (v2 and v1) REST APIs. |
| `atlassian_describe_operation` | Everything about one catalog operation: route, tier and the tool that runs it, parameters, the request body schema with $refs expanded to depth levels, OAuth scopes (for scoped API tokens), and deprecation or app-only notes. |
| `atlassian_execute_read` | Run a read-only Atlassian REST operation from the catalog (tier read in atlassian_discover): every GET, plus POST searches and checks such as JQL search (jira.searchAndReconsileIssuesUsingJqlPost) and bulk fetches. |
| `atlassian_execute_write` | Run an Atlassian REST operation from the catalog that creates or changes something (tier write in atlassian_discover), such as creating an issue, transitioning it, adding a comment or updating a page. |
| `atlassian_execute_destructive` | Run an Atlassian REST operation from the catalog that deletes, archives, trashes, redacts or removes something (tier destructive in atlassian_discover). |
| `atlassian_request` | Send a request to any Jira or Confluence REST endpoint, for one the catalog doesn't have. |
| `atlassian_graphql_query` | Run a read-only GraphQL query against Atlassian's GraphQL API on the site (https://<site>/gateway/api/graphql). |
| `atlassian_graphql_mutation` | Run a GraphQL mutation against Atlassian's GraphQL API on the site. |

### Rovo

| Tool | What it does |
|---|---|
| `atlassian_rovo_sign_in` | Open the Atlassian sign-in page in the user's browser so this server can use Rovo search and the Teamwork Graph for a site (Atlassian only offers these through its hosted Rovo MCP server, which needs a browser sign-in; API tokens aren't used for it). |
| `atlassian_rovo_sign_out` | Forget the Rovo sign-in for a site: removes its tokens from the Keychain. |
| `atlassian_rovo_search` | Search across Jira, Confluence and connected third-party apps (Google Drive, Slack, GitHub and others the organisation connected) with Rovo Search, Atlassian's semantic enterprise search. |
| `atlassian_teamwork_graph_context` | Get everything connected to one item in Atlassian's Teamwork Graph in a single call: linked work items, pages, people, teams, goals, projects, pull requests, builds, deployments, designs, Loom videos and third-party items. |
| `atlassian_teamwork_graph_object` | Fetch the full available data for up to 25 items (Atlassian or third-party) by ARI or URL, e.g. ARIs returned by atlassian_teamwork_graph_context or atlassian_rovo_search. |
| `atlassian_teamwork_graph_link` | Add a relationship in the Teamwork Graph: link two Jira work items, mark one as blocking another, add a remote link to a work item, or connect a work item to an Atlassian project or goal. |

### Updates

Used by the update card (see [Updates](#updates)); only `check_for_updates` is offered to Claude.

| Tool | What it does |
|---|---|
| `check_for_updates` | Check whether a newer version of this extension is on its landing page and show the owner a card to update it (Update now / Not now). |
| `install_update` | Download the newer version, check its SHA-256, and open Claude Desktop's install dialog for it. |
| `snooze_update` | Don't offer the newest version again for a week. |

## Security and privacy

- Tokens (Atlassian API tokens and Data Center personal access tokens) live only in the macOS Keychain, one item per site, saved from a hidden-input prompt. They never go through chat, command-line arguments or files, and no tool returns them.
- Requests go only to your Atlassian sites, to `api.atlassian.com` (for scoped tokens), to `mcp.atlassian.com` (for Rovo) and, for the update check, to this extension's landing page. The raw request tool accepts only paths on the site itself.
- An update is only offered, never installed by Claude: the card's buttons are the only way to start one, the download must match its published SHA-256 and be this extension at the offered version, and Claude Desktop's own install dialog still asks you. Turn the check off with the extension's **Check for updates** setting.
- Every operation is labelled read, write or destructive from what it does, not just its HTTP method, so Claude Desktop asks before anything that changes or deletes data.
- The Rovo sign-in is OAuth 2.1 with PKCE in your own browser. A listener on `localhost:47813` runs only while a sign-in is waiting, and the tokens are kept in the Keychain.
- Atlassian records Rovo tool calls in your organisation's audit log, and they use Rovo credits.
- The installer's SHA-256 check catches a corrupted or partial download, not a compromised site: the checksum and the installer are served from the same site. Read `install.sh` before running it if that matters to you.

## Troubleshooting

See INSTALL.md for installer errors and tokens.

- **"No API token is saved"** (or **"No personal access token is saved"** on a Data Center site): ask Claude to run `atlassian_set_token` for that site. For a Cloud site you can also run the installer again in a terminal.
- **"More than one Atlassian site is set up"**: say which site, e.g. "on acme".
- **Error 401**: the token expired or was revoked. Save a new one with `atlassian_set_token`.
- **Error 403**: your account (or a scoped token) isn't allowed to do that. Atlassian answers 404 for things you can't see.
- **A Data Center site can't be reached**: self-hosted Jira is often only reachable on the company network or VPN.
- **"didn't answer … within 30 s"**: the site was too slow or out of reach for that request (the error names the site and API path). Try again; for a self-hosted Jira that is just slow, raise the extension's **Request timeout** setting (seconds).
- **A ticket you raised on a portal isn't found by a Jira search**: JQL only sees projects your account can browse, and on a service desk where you're only a customer it can't. Ask Claude to find your ticket instead (`atlassian_find_my_tickets`), which reads the portal requests of every site.
- **"didn't report a cloud id" or a prompt for an email and API token on a Data Center site**: the extension is older than 1.1.0, or Claude used the wrong address. A self-hosted Jira and a Cloud site can share a name (`jira.uhub.biz` and `uhub.atlassian.net` are different sites), so list only the one you use in the extension's **Atlassian sites** setting, and give its full host, e.g. `jira.example.com`.
- **No update card**: updates are offered from version 1.1.0, at most once a day, while **Check for updates** is on in the extension's settings. Ask Claude to check for updates, or run the install command again.
- **"Rovo isn't signed in"**: ask Claude to sign in to Rovo for that site and approve access in the browser.

## Notes

- Every tool takes a `site`. With one site set up it's optional; with several, Claude has to name one, so nothing is written to the wrong site by default. The two read-only searches, `atlassian_find_my_tickets` and `atlassian_service_desk_list_requests`, are the exception: without a `site` they read every set-up site and say what each one gave.
- A bare name such as `acme` means the set-up site with `acme` in its host (so `uhub` finds `jira.uhub.biz`), and otherwise `acme.atlassian.net`. If it matches more than one set-up site, Claude is asked for the full host.
- Operations that only Atlassian Connect or Forge apps can call (Jira DevOps builds and deployments, for example) are in the catalog but marked: a personal token gets 401 or 403 for them.
- The catalog is rebuilt from Atlassian's published OpenAPI specs (`npm run specs:update`), so new endpoints arrive with a release. Until then, `atlassian_request` reaches anything on the site.

---

<sub>Generated from the project README for version 1.2.1. It is rebuilt automatically with each release.</sub>
