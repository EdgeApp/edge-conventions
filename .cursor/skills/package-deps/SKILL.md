---
name: package-deps
description: Package local dependency repos and link them to edge-react-gui for testing. Use when the user asks to pack, link, or test local dependency changes in the GUI app.
---

# Pack Dependencies

Package local dependency repos as tarballs and link them into edge-react-gui for testing.

## Instructions

1. Identify the dependency repo directories from the user's prompt. Repos live as siblings of edge-react-gui under the same parent directory (e.g. `../edge-core-js`).

2. Run the packdep script, passing the GUI directory and each dependency directory:

```bash
node <skill-dir>/scripts/packdep.js --gui <guiDir> <depDir1> [depDir2] ...
```

The script handles everything: `npm pack`, timestamped rename, old tarball cleanup, copy to the GUI root, `package.json` update, and `yarn` install.
