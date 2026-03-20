#!/usr/bin/env bash
# port-to-opencode.sh — Convert Cursor .mdc/.md files to OpenCode-compatible JSON + MD mirrors.
# Single self-contained script (bash + inline node). No Python dependency.
#
# Usage:
#   port-to-opencode.sh                    # Convert all rules and skills
#   port-to-opencode.sh --dry-run          # Show what would be done
#   port-to-opencode.sh --validate         # Validate existing JSON mirrors
#   port-to-opencode.sh file1.mdc file2.md # Convert specific files
set -euo pipefail

DRY_RUN=false
VALIDATE=false
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --validate) VALIDATE=true; shift ;;
    --sync) shift ;; # accepted for compat, no-op
    *) FILES+=("$1"); shift ;;
  esac
done

exec node -e '
const fs = require("fs")
const pathMod = require("path")
const os = require("os")

const CURSOR_DIR = pathMod.join(os.homedir(), ".cursor")
const OPENCODE_DIR = pathMod.join(os.homedir(), ".config", "opencode")
const DRY_RUN = process.argv[1] === "true"
const VALIDATE = process.argv[2] === "true"
const inputFiles = process.argv.slice(3).filter(f => f)

function parseYamlFrontmatter(content) {
  const match = content.match(/^---\s*\n([\s\S]*?)\n---\s*\n/)
  if (!match) return {}
  const fm = {}
  for (const line of match[1].split("\n")) {
    const idx = line.indexOf(":")
    if (idx === -1) continue
    const key = line.substring(0, idx).trim()
    let value = line.substring(idx + 1).trim()
    if (value.startsWith("[") && value.endsWith("]")) {
      try { value = JSON.parse(value.replace(/\x27/g, "\x22")) } catch {}
    } else if (value === "true" || value === "false") {
      value = value === "true"
    }
    fm[key] = value
  }
  return fm
}

function extractTagContent(content, tag) {
  const re = new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)</" + tag + ">")
  const m = content.match(re)
  return m ? m[1].trim() : ""
}

function extractGoal(content) { return extractTagContent(content, "goal") }

function extractRules(content) {
  const section = extractTagContent(content, "rules")
  if (!section) return []
  const rules = []
  const re = /<rule\s+id="([^"]+)"[^>]*>([\s\S]*?)<\/rule>/g
  let m
  while ((m = re.exec(section)) !== null) {
    let instruction = m[2].trim().replace(/\*\*/g, "").replace(/\s+/g, " ")
    rules.push({ id: m[1], instruction })
  }
  return rules
}

function extractSteps(content) {
  const steps = []
  const re = /<step\s+id="([^"]+)"\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/step>/g
  let m
  while ((m = re.exec(content)) !== null) {
    steps.push({ id: m[1], name: m[2], instruction: m[3].trim() })
  }
  return steps
}

function extractScriptRefs(content) {
  const refs = new Set()
  const re = /[~]?\/[\w/\-.]+\.(sh|js)/g
  let m
  while ((m = re.exec(content)) !== null) refs.add(m[0])
  return [...refs].sort()
}

function convertMdcToJson(filePath) {
  const content = fs.readFileSync(filePath, "utf8")
  const fm = parseYamlFrontmatter(content)
  const basename = pathMod.basename(filePath, ".mdc")
  return {
    id: basename, title: basename,
    description: fm.description || extractGoal(content),
    globs: fm.globs || [], alwaysApply: fm.alwaysApply || false,
    goal: extractGoal(content), rules: extractRules(content),
    steps: extractSteps(content), scripts: extractScriptRefs(content)
  }
}

function convertCommandToJson(filePath) {
  const content = fs.readFileSync(filePath, "utf8")
  const basename = pathMod.basename(filePath, ".md")
  const goal = extractGoal(content)
  return {
    id: basename, title: basename, description: goal, goal,
    rules: extractRules(content), steps: extractSteps(content),
    scripts: extractScriptRefs(content)
  }
}

function convertSkillToJson(filePath) {
  const content = fs.readFileSync(filePath, "utf8")
  const fm = parseYamlFrontmatter(content)
  const basename = pathMod.basename(pathMod.dirname(filePath))
  return {
    id: basename, title: fm.name || basename, name: fm.name || basename,
    description: fm.description || extractGoal(content),
    goal: extractGoal(content), rules: extractRules(content),
    steps: extractSteps(content), scripts: extractScriptRefs(content)
  }
}

function convertToMd(content) {
  let r = content
  r = r.replace(/<goal>([\s\S]*?)<\/goal>/g, "## Goal\n\n$1\n")
  r = r.replace(/<rules[^>]*>/g, "## Rules\n\n")
  r = r.replace(/<\/rules>/g, "")
  r = r.replace(/<rule id="([^"]+)">/g, "- **$1**: ")
  r = r.replace(/<\/rule>/g, "")
  r = r.replace(/<step id="([^"]+)" name="([^"]+)">/g, "### Step $1: $2\n\n")
  r = r.replace(/<\/step>/g, "")
  r = r.replace(/<sub-step name="([^"]+)">/g, "#### $1\n\n")
  r = r.replace(/<\/sub-step>/g, "")
  r = r.replace(/<edge-cases>/g, "## Edge Cases\n\n")
  r = r.replace(/<\/edge-cases>/g, "")
  r = r.replace(/<case name="([^"]+)">/g, "### $1\n\n")
  r = r.replace(/<\/case>/g, "")
  r = r.replace(/<sequence name="([^"]+)">/g, "## Sequence: $1\n\n")
  r = r.replace(/<\/sequence>/g, "")
  r = r.replace(/<scope>/g, "## Scope\n\n")
  r = r.replace(/<\/scope>/g, "")
  r = r.replace(/<standards[^>]*>/g, "## Standards\n\n")
  r = r.replace(/<\/standards>/g, "")
  r = r.replace(/<standard id="([^"]+)">/g, "- **$1**: ")
  r = r.replace(/<\/standard>/g, "")
  while (r.includes("\n\n\n")) r = r.replace(/\n\n\n/g, "\n\n")
  return r
}

function processFile(filePath) {
  let outputDir, outputBase, converter
  if (filePath.includes("/rules/") && filePath.endsWith(".mdc")) {
    outputDir = pathMod.join(OPENCODE_DIR, "rules")
    outputBase = pathMod.basename(filePath, ".mdc")
    converter = convertMdcToJson
  } else if (filePath.includes("/skills/") && pathMod.basename(filePath) === "SKILL.md") {
    outputDir = pathMod.join(OPENCODE_DIR, "skills", pathMod.basename(pathMod.dirname(filePath)))
    outputBase = "SKILL"
    converter = convertSkillToJson
  } else {
    return "Skipping: " + filePath + " (unknown type)"
  }

  const jsonPath = pathMod.join(outputDir, outputBase + ".json")
  const mdPath = pathMod.join(outputDir, outputBase + ".md")

  if (DRY_RUN) return "Would create: " + jsonPath + "\n         Would create: " + mdPath

  fs.mkdirSync(outputDir, { recursive: true })
  const jsonData = converter(filePath)
  const content = fs.readFileSync(filePath, "utf8")
  fs.writeFileSync(jsonPath, JSON.stringify(jsonData, null, 2) + "\n")
  fs.writeFileSync(mdPath, convertToMd(content))
  return "Converted: " + filePath + " -> " + jsonPath
}

function validateJson(jsonPath) {
  try {
    const data = JSON.parse(fs.readFileSync(jsonPath, "utf8"))
    const missing = ["id", "title", "description"].filter(f => !(f in data))
    if (missing.length) return "INVALID: " + jsonPath + " (missing: " + missing.join(", ") + ")"
    return "VALID: " + jsonPath
  } catch (e) {
    return "INVALID: " + jsonPath + " (not valid JSON: " + e.message + ")"
  }
}

function walkDir(dir, predicate) {
  const results = []
  try {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = pathMod.join(dir, entry.name)
      if (entry.isDirectory()) results.push(...walkDir(full, predicate))
      else if (predicate(full, entry.name)) results.push(full)
    }
  } catch {}
  return results
}

if (VALIDATE) {
  console.log("Validating JSON mirrors...")
  for (const f of walkDir(OPENCODE_DIR, (fp, n) => n.endsWith(".json"))) console.log(validateJson(f))
  process.exit(0)
}

const files = inputFiles.length > 0
  ? inputFiles.map(f => f.startsWith("~") ? f.replace("~", os.homedir()) : f)
  : [
      ...walkDir(pathMod.join(CURSOR_DIR, "rules"), (fp, n) => n.endsWith(".mdc")),
      ...walkDir(pathMod.join(CURSOR_DIR, "skills"), (fp, n) => n === "SKILL.md")
    ]

console.log("Found " + files.length + " files to process")
for (const f of files) console.log(processFile(f))
console.log("\nDone. Processed " + files.length + " files.")
if (DRY_RUN) console.log("Run without --dry-run to write files.")
' "$DRY_RUN" "$VALIDATE" ${FILES[@]+"${FILES[@]}"}
