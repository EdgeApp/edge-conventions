---
name: review-strings
description: Reviews user-facing strings for localization and naming conventions. Use when reviewing UI components or localization files.
---

Review the branch/pull request in context for string conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for hardcoded strings in UI components
3. Check string key naming conventions
4. Report findings with specific file:line references

---

## No Hardcoded User-Facing Strings

Do not hardcode any user-facing strings in UI components. Instead, add them to the `en_US.json` file (or whichever file is imported by `strings.ts`).

```typescript
// Incorrect - hardcoded string
<Button label="Get Started" />

// Correct - use localized string
<Button label={lstrings.get_started_button} />
```

---

## Reuse Existing Strings

Do not create new strings if an existing one can be used. Search the localization file before adding new keys.

---

## Context-Based Key Names

String key names should describe their semantic meaning, not their location in the UI:

```json
// Incorrect - specifies screen location
{
  "signup_screen_get_started": "Get Started"
}

// Correct - describes the action/context
{
  "get_started_button": "Get Started"
}
```

This allows the same string to be reused across different screens without confusion.

---

## Avoid Informal "Tap to X" Phrasing

User prompts should describe the action, not the gesture:

```json
// Incorrect - describes the gesture
{
  "select_country_prompt": "Tap to select a country"
}

// Correct - describes the outcome
{
  "select_country_prompt": "Select a country"
}
```

"Tap to X" is overly informal and doesn't translate well to all platforms.

---

## Localization Belongs at GUI Level

Error messages and user-facing strings should be localized in the GUI layer, not in API or plugin code:

```typescript
// Incorrect - localized string in API layer
throw new Error(lstrings.network_error)

// Correct - throw structured error, localize in GUI
throw new NetworkError('CONNECTION_FAILED')

// In GUI:
const message = translateError(error)  // Returns localized string
```

API layers should throw structured errors that the GUI translates for display.
