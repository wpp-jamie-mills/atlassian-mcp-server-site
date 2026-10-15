# Atlassian MCP Server

**Give Claude every Jira, Confluence and Rovo API. It runs locally on your Mac, signs in as you on each of your Atlassian sites, and can only do what your account can.**

Version **1.0.1** · macOS · Claude Desktop extension

- [Install: for people](#install-for-people)
- [Install: for AI agents](#install-for-ai-agents)
- [What you can do](#what-you-can-do)
- [API tokens](#api-tokens)
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

You need macOS, Claude Desktop and an Atlassian API token for each site. To update later, run the same command again.

## Install: for AI agents

Use these steps if you are an AI agent installing this for a user.

1. **Check the machine.** Continue only if `uname -s` prints `Darwin` and `/Applications/Claude.app` exists. Otherwise tell the user it needs macOS with Claude Desktop installed.
2. **Run the installer** with this one command. It downloads the extension, checks its SHA-256 (nothing is installed before the check passes) and opens Claude Desktop's install dialog. `ATLASSIAN_INSTALL_TTY=/dev/null` means there is no terminal: it never quits or restarts an app, answers no to every question and never opens the token prompt. `--no-wait` makes it exit 0 once the dialog is open. It exits non-zero, with the reason on stderr, if anything fails before then. To choose the sites, add `--site <site>` once per site (e.g. `--site acme.atlassian.net`).

```bash
curl -fsSL https://wpp-jamie-mills.github.io/atlassian-mcp-server-site/install.sh | ATLASSIAN_INSTALL_TTY=/dev/null bash -s -- --no-wait
```

3. **Hand over to the user.** Ask them to click **Install** in Claude Desktop. For each site without a token, call `atlassian_set_token` with the site: a secure prompt on their Mac. Never ask for the token in chat.
4. **Verify.** Run the installer again with `--status` (after `bash -s --`), or call `atlassian_ensure_ready` in Claude Desktop: it reports each site and the single next step.
5. **Rovo (optional).** Call `atlassian_rovo_sign_in` with each site; the user approves access in their browser once per site.

## What you can do

**Every Jira and Confluence REST API.** All 1,191 operations Atlassian publishes: Jira (629), Jira Software boards, sprints, epics and backlogs (105), Jira Service Management (75), and Confluence v2 (252) and v1 (130). Claude finds the operation it needs with `atlassian_discover` and runs it, so nothing is out of reach, from workflows and permission schemes to page restrictions and customer requests.

**Everyday work in Markdown.** Search with JQL or CQL, read, create, edit, move and comment on issues, and read, create, update and comment on pages and blog posts. Claude writes Markdown; the server converts it to Atlassian's format and back.

**Atlassian GraphQL.** Queries and mutations against the platform graph behind Jira, Confluence, Goals, Projects and Teams.

**Rovo.** Rovo search across Jira, Confluence and the apps your organisation connected, and the Teamwork Graph: everything linked to an issue, page, person or goal in one call. Atlassian offers these only through its hosted Rovo MCP server, so this server signs in to it for you.

**Several sites at once.** Each site has its own email and token, so sites can use different accounts. Choose them with the installer's `--site`, or add one any time with `atlassian_set_token`.

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
```

## API tokens

Create a token at https://id.atlassian.com/manage-profile/security/api-tokens and give it to the installer or `atlassian_set_token`, never to Claude in chat. A classic token can do whatever your account can. A scoped token can do only what its scopes allow; the server notices and sends its requests through `api.atlassian.com`, which scoped tokens need. Each site keeps its own email and token, so a site where you use a different Atlassian account just gets a different token. Some organisations block API tokens for managed accounts; if Atlassian rejects a token you know is right, ask your Atlassian admin.

Rovo doesn't use the API token: Atlassian only allows a browser sign-in (OAuth) for its Rovo MCP server. Atlassian's consent page grants one site at a time, so sign in once for each site you want Rovo on.

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

## Security and privacy

- API tokens live only in the macOS Keychain, one item per site, saved from a hidden-input prompt. They never go through chat, command-line arguments or files, and no tool returns them.
- Requests go only to your Atlassian sites, to `api.atlassian.com` (for scoped tokens) and to `mcp.atlassian.com` (for Rovo). The raw request tool accepts only paths on the site itself.
- Every operation is labelled read, write or destructive from what it does, not just its HTTP method, so Claude Desktop asks before anything that changes or deletes data.
- The Rovo sign-in is OAuth 2.1 with PKCE in your own browser. A listener on `localhost:47813` runs only while a sign-in is waiting, and the tokens are kept in the Keychain.
- Atlassian records Rovo tool calls in your organisation's audit log, and they use Rovo credits.
- The installer's SHA-256 check catches a corrupted or partial download, not a compromised site: the checksum and the installer are served from the same site. Read `install.sh` before running it if that matters to you.

## Troubleshooting

See INSTALL.md for installer errors and tokens.

- **"No API token is saved"**: ask Claude to run `atlassian_set_token` for that site, or run the installer again in a terminal.
- **"More than one Atlassian site is set up"**: say which site, e.g. "on acme".
- **Error 401**: the token expired or was revoked. Save a new one with `atlassian_set_token`.
- **Error 403**: your account (or a scoped token) isn't allowed to do that. Atlassian answers 404 for things you can't see.
- **"Rovo isn't signed in"**: ask Claude to sign in to Rovo for that site and approve access in the browser.

## Notes

- Every tool takes a `site`. With one site set up it's optional; with several, Claude has to name one, so nothing is written to the wrong site by default.
- Operations that only Atlassian Connect or Forge apps can call (Jira DevOps builds and deployments, for example) are in the catalog but marked: a personal token gets 401 or 403 for them.
- The catalog is rebuilt from Atlassian's published OpenAPI specs (`npm run specs:update`), so new endpoints arrive with a release. Until then, `atlassian_request` reaches anything on the site.

---

<sub>Generated from the project README for version 1.0.1. It is rebuilt automatically with each release.</sub>
