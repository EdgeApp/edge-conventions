'use strict'

const { execSync } = require('child_process')

function ensureGhToken() {
  if (process.env.GH_TOKEN) return
  try {
    const b64 = execSync(
      'security find-generic-password -s "gh:github.com" -w 2>/dev/null',
      { encoding: 'utf8' }
    ).trim()
    const match = b64.match(/^go-keyring-base64:(.+)$/)
    if (match) {
      process.env.GH_TOKEN = Buffer.from(match[1], 'base64').toString('utf8')
    } else if (b64.startsWith('gho_') || b64.startsWith('ghp_')) {
      process.env.GH_TOKEN = b64
    }
  } catch (_) {}
}

module.exports = { ensureGhToken }
