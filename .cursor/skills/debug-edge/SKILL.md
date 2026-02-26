---
name: debug-edge
description: Compile, launch, and debug the Edge wallet app on an iOS simulator. Use when the user wants to build, run, debug, or test the Edge app on iOS, or needs to interact with the simulator UI.
---

# Debug Edge App on iOS Simulator

This skill guides you through compiling, launching, and controlling the Edge wallet app on an iOS simulator using MCP tools.

## Prerequisites

- Xcode installed with iOS simulators
- Working directory: `edge-react-gui`
- MCP servers available: `user-xcodebuild`, `user-mobile-mcp`
- Artifact directory input: `ARTIFACTS_DIR` (when called from execute-plan, use `/tmp/YYYYMMDDTHHMM-<title>-Plan`)
- Artifact naming rule: prefix all screenshots and videos with `YYYYMMDDTHHMM-`

## Workflow Overview

```
Task Progress:
- [ ] Step 0: Prepare artifact directory
- [ ] Step 1: Install dependencies and prepare
- [ ] Step 2: Clean iOS build artifacts
- [ ] Step 3: Prepare iOS-specific files
- [ ] Step 4: Clean Xcode build
- [ ] Step 5: Start Metro bundler
- [ ] Step 6: Build and launch app
- [ ] Step 7: Log into test account (if needed)
- [ ] Step 8: Stop recording and report artifacts
```

## Step 0: Prepare Artifact Directory

Before any simulator automation:

```bash
ARTIFACTS_DIR="${ARTIFACTS_DIR:-/tmp/debug-edge-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
```

Use this directory for:
- simulator recording video
- screenshots captured while debugging

## Step 1: Install Dependencies and Prepare

Run these commands sequentially in the `edge-react-gui` directory:

```bash
yarn
yarn prepare
```

## Step 2: Clean iOS Build Artifacts

Remove cached iOS build files:

```bash
rm -rf ios/Pods && rm -rf ios/build
```

## Step 3: Prepare iOS-Specific Files

Run iOS preparation which installs CocoaPods and configures the iOS project:

```bash
yarn prepare.ios
```

This can take several minutes.

## Step 4: Clean Xcode Build

Use the Xcode MCP server to clean build products:

```
MCP: user-xcodebuild
Tool: clean
Arguments: { "platform": "iOS Simulator" }
```

## Step 5: Start Metro Bundler

In a **separate terminal**, start the React Native Metro bundler:

```bash
yarn start --client-logs
```

**Important**: Keep this terminal visible. React Native JavaScript logs appear here, making it essential for debugging JS-side issues.

## Step 6: Build and Launch App

Use the Xcode MCP server to build and run on simulator:

```
MCP: user-xcodebuild
Tool: build_run_sim
Arguments: {}
```

This will:
1. Build the app
2. Boot an iOS simulator
3. Install and launch the Edge app

The build can take 10-15 minutes on first run. Run with `block_until_ms: 900000` (15 min) to avoid premature backgrounding.

## Step 7: Log Into Test Account (If Needed)

If debugging unrelated to account creation, use an existing test account.

### Start Simulator Recording Before Automation

Start recording immediately before taps/swipes/type actions:

```bash
VIDEO_STAMP="$(date +"%Y%m%dT%H%M")"
VIDEO_PATH="$ARTIFACTS_DIR/${VIDEO_STAMP}-sim-automation.mp4"
```

Then:

```
MCP: user-xcodebuild
Tool: record_sim_video
Arguments: { "start": true, "fps": 30, "outputFile": "<VIDEO_PATH>" }
```

### Find UI Elements

First, get the current UI state to locate buttons:

```
MCP: user-xcodebuild
Tool: describe_ui
Arguments: {}
```

### Enter PIN 1111

Tap the "1" button four times using the label parameter:

```
MCP: user-xcodebuild
Tool: tap
Arguments: { "label": "1", "postDelay": 0.3 }
```

Repeat 4 times total for PIN "1111".

### Stop Simulator Recording After Automation

When automation is finished (or before aborting due to failure), stop recording:

```
MCP: user-xcodebuild
Tool: record_sim_video
Arguments: { "stop": true }
```

Record `VIDEO_PATH` in your execution summary.

**Alternative using mobile-mcp**: If you need to use mobile-mcp instead:

```
MCP: user-mobile-mcp
Tool: mobile_list_available_devices
Arguments: { "noParams": {} }
```

Then list elements to find the "1" button coordinates:

```
MCP: user-mobile-mcp
Tool: mobile_list_elements_on_screen
Arguments: { "device": "<device-id>" }
```

Then tap at those coordinates:

```
MCP: user-mobile-mcp
Tool: mobile_click_on_screen_at_coordinates
Arguments: { "device": "<device-id>", "x": <x>, "y": <y> }
```

## Debugging Tips

### View JavaScript Logs

The terminal running `yarn start` shows all `console.log` output from React Native JavaScript code.

### Debugging Plugin Repositories (WebView Code)

The following repositories execute inside a headless WebView within the app:

- **edge-core-js** - Core account and wallet management
- **edge-currency-accountbased** - Account-based currency plugins (ETH, etc.)
- **edge-exchange-plugins** - Swap/exchange provider integrations
- **edge-currency-plugins** - UTXO-based currency plugins (BTC, etc.)

**Problem**: Regular `console.log` statements in these repos do NOT appear in the Metro bundler logs because the WebView has its own JavaScript context.

**Solution**: Use the `log.warn()` method from the `EdgeLog` interface, which routes messages through edge-core-js back to edge-react-gui where they appear in Metro logs.

**In currency engines** (edge-currency-accountbased, edge-currency-plugins):

```typescript
// Access via this.log on engine classes
this.log.warn('Debug message', someData)
```

**In exchange plugins** (edge-exchange-plugins):

```typescript
// log is passed to the plugin function
log.warn('Debug message', someData)
```

**Available log methods**:
- `log('message')` - Info level (may be filtered out)
- `log.warn('message')` - Warning level (recommended for debugging)
- `log.error('message')` - Error level

Using `log.warn()` ensures messages appear in Metro logs regardless of log level filtering.

**Note**: Both React Native and WebView code have full access to `fetch` from localhost. Any instrumentation or debugging tools that rely on fetch will work normally.

### Running Debug Servers for Plugin Repos

For live debugging with hot-reload, run a debug server for the plugin repository you're working on. This serves the JavaScript bundle from localhost instead of the bundled version.

**Step 1: Enable debug mode in `env.json`**

Edit `edge-react-gui/env.json` and set the appropriate flag to `true`:

| Repository | env.json Flag |
|------------|---------------|
| edge-core-js | `DEBUG_CORE` |
| edge-currency-accountbased | `DEBUG_ACCOUNTBASED` |
| edge-exchange-plugins | `DEBUG_EXCHANGES` |
| edge-currency-plugins | `DEBUG_CURRENCY_PLUGINS` |

**Step 2: Start the debug server**

In a **separate terminal** for each repo you want to debug:

```bash
# Navigate to the plugin repo
cd /path/to/edge-currency-accountbased  # or other repo

# Install dependencies and compile
yarn

# Start the debug server
yarn start
```

The debug server watches for changes and rebuilds automatically. Each repo needs its own terminal running `yarn start`. Rebuilds usually take less than 1 second, but can occasionally take over 10 seconds. Always wait for the rebuild to finish before starting another testing loop.

**Step 3: Rebuild the app**

After changing `env.json`, rebuild edge-react-gui to pick up the new debug flags. The app will then load JavaScript from the debug server instead of the bundled version.

**Example: Debugging exchange plugins**

1. Set `"DEBUG_EXCHANGES": true` in `edge-react-gui/env.json`
2. In terminal 1: `cd edge-exchange-plugins && yarn && yarn start`
3. In terminal 2: `cd edge-react-gui && yarn start`
4. Rebuild and launch the app
5. Changes to edge-exchange-plugins will hot-reload

### View Native Logs

Use Xcode MCP to capture native iOS logs:

```
MCP: user-xcodebuild
Tool: start_sim_log_cap
```

### Take Screenshots

When you need a screenshot during debugging:

```
MCP: user-xcodebuild
Tool: screenshot
Arguments: { "returnFormat": "path" }
```

Then copy or move it into `ARTIFACTS_DIR` with required prefix:

```bash
SCREEN_STAMP="$(date +"%Y%m%dT%H%M")"
cp "<returned-path>" "$ARTIFACTS_DIR/${SCREEN_STAMP}-<label>.png"
```

If copy fails (same filesystem move is preferred), use:

```bash
mv "<returned-path>" "$ARTIFACTS_DIR/${SCREEN_STAMP}-<label>.png"
```

Every screenshot filename must start with `YYYYMMDDTHHMM-`.

### Type Text

To type into focused text fields:

```
MCP: user-xcodebuild
Tool: type_text
Arguments: { "text": "your text here" }
```

## Step 8: Stop Recording and Report Artifacts

Before ending the debug run:

1. Ensure simulator recording is stopped (`record_sim_video` with `{ "stop": true }`)
2. List saved artifacts in `ARTIFACTS_DIR`
3. Return artifact paths in the final report:
   - video path(s)
   - screenshot path(s)

## Troubleshooting

### Build Fails

1. Re-run `yarn prepare.ios`
2. Clean build with Xcode MCP `clean` tool
3. Check Xcode is up to date

### Simulator Won't Boot

List available simulators:

```
MCP: user-xcodebuild
Tool: list_sims
Arguments: { "enabled": true }
```

### Metro Bundler Issues

If Metro bundler has issues, stop it and restart with cache clear:

```bash
yarn start --reset-cache
```
