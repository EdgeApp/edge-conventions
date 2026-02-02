# install-mcp

Install and configure MCP servers for Edge development automation.

## MCP Servers

Add the following to `~/.cursor/mcp.json` under the `mcpServers` object, then restart Cursor.

### GitHub MCP Server

Provides GitHub API integration for managing pull requests, issues, and repository operations.

**Source**: [github.com/github/github-mcp-server](https://github.com/github/github-mcp-server)

**Prerequisites**: Docker installed

**Setup**:
1. Generate a GitHub Personal Access Token with scopes: `repo`, `read:org`
2. Add to `~/.cursor/mcp.json`:

```json
{
  "github": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-e",
      "GITHUB_PERSONAL_ACCESS_TOKEN",
      "ghcr.io/github/github-mcp-server"
    ],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-github-pat>"
    }
  }
}
```

### Xcode Build MCP Server

Provides Xcode build automation, iOS simulator control, and UI interaction.

**npm package**: `xcodebuildmcp`

**Capabilities**: Build iOS projects, launch simulators, take screenshots, tap/type UI elements, capture logs

```json
{
  "xcodebuild": {
    "command": "npx",
    "args": ["-y", "xcodebuildmcp@latest"]
  }
}
```

### Mobile MCP Server

Provides cross-platform mobile device automation for iOS simulators and Android emulators.

**npm package**: `@mobilenext/mobile-mcp`

**Capabilities**: List devices, launch/terminate apps, screenshots, tap/swipe/type, list UI elements

```json
{
  "mobile-mcp": {
    "command": "npx",
    "args": ["-y", "@mobilenext/mobile-mcp@latest"]
  }
}
```

## Complete Configuration Example

```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-github-pat>"
      }
    },
    "xcodebuild": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest"]
    },
    "mobile-mcp": {
      "command": "npx",
      "args": ["-y", "@mobilenext/mobile-mcp@latest"]
    }
  }
}
```
