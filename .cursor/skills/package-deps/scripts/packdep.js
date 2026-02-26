#!/usr/bin/env node

const { execSync } = require('child_process')
const fs = require('fs')
const path = require('path')

// --- Parse args ---

const args = process.argv.slice(2)
let guiDir = null
const depDirs = []

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--gui') {
    guiDir = args[++i]
  } else {
    depDirs.push(args[i])
  }
}

if (!guiDir || depDirs.length === 0) {
  console.error(
    'Usage: node packdep.js --gui <guiDir> <depDir1> [depDir2] ...'
  )
  process.exit(1)
}

guiDir = path.resolve(guiDir)
const pkgJsonPath = path.join(guiDir, 'package.json')

// --- UTC timestamp: YYYYMMDDTHHMM ---

const now = new Date()
const ts =
  now.getUTCFullYear().toString() +
  String(now.getUTCMonth() + 1).padStart(2, '0') +
  String(now.getUTCDate()).padStart(2, '0') +
  'T' +
  String(now.getUTCHours()).padStart(2, '0') +
  String(now.getUTCMinutes()).padStart(2, '0')

// --- Read GUI package.json ---

const pkgJson = JSON.parse(fs.readFileSync(pkgJsonPath, 'utf8'))

// --- Process each dependency ---

for (const depDir of depDirs) {
  const resolved = path.resolve(depDir)
  console.log(`\nPacking ${resolved} ...`)

  // Read dep's package.json for the package name
  const depPkg = JSON.parse(
    fs.readFileSync(path.join(resolved, 'package.json'), 'utf8')
  )
  const depName = depPkg.name

  // npm pack — last non-empty line of stdout is the tarball filename
  const packOutput = execSync('npm pack', {
    cwd: resolved,
    encoding: 'utf8'
  }).trim()
  const tarball = packOutput.split('\n').pop().trim()
  const tarballPath = path.join(resolved, tarball)

  // Timestamped filename: edge-core-js-2.43.1-20260223T2343.tgz
  const newTarball = tarball.replace(/\.tgz$/, `-${ts}.tgz`)
  const destPath = path.join(guiDir, newTarball)

  // Remove old tarballs for this package from the GUI directory.
  // Tarball names follow npm's convention: scoped "@foo/bar" → "foo-bar-*"
  const namePrefix = depName.replace(/^@/, '').replace(/\//, '-')
  for (const file of fs.readdirSync(guiDir)) {
    if (file.startsWith(namePrefix + '-') && file.endsWith('.tgz')) {
      console.log(`  Removing old tarball: ${file}`)
      fs.unlinkSync(path.join(guiDir, file))
    }
  }

  // Copy tarball to GUI dir, then clean up the original
  fs.copyFileSync(tarballPath, destPath)
  fs.unlinkSync(tarballPath)
  console.log(`  Created ${newTarball}`)

  // Update the matching dependency entry in package.json
  const sections = ['dependencies', 'devDependencies']
  let found = false
  for (const section of sections) {
    if (pkgJson[section] && depName in pkgJson[section]) {
      pkgJson[section][depName] = `./${newTarball}`
      console.log(`  Updated ${section}["${depName}"]`)
      found = true
      break
    }
  }
  if (!found) {
    console.warn(
      `  Warning: "${depName}" not found in dependencies or devDependencies`
    )
  }
}

// --- Write updated package.json ---

fs.writeFileSync(pkgJsonPath, JSON.stringify(pkgJson, null, 2) + '\n')
console.log('\npackage.json updated. Running yarn ...')

// --- Install tarballs ---

execSync('yarn', { cwd: guiDir, stdio: 'inherit' })
console.log('\nDone.')
