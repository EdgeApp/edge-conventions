# packdep

Package a local dependency repo and link it to edge-react-gui for testing.

## Instructions

For each dependency repo specified in the prompt:

1. Navigate to the dependency repo directory
2. Run `npm pack` to create a tarball
3. Rename the tarball to include a timestamp suffix in **UTC time** using the format `YYYYMMDDTHHMM` (e.g., `edge-core-js-2.38.4-20260202T0406.tgz`)
4. Copy the renamed tarball to the edge-react-gui root directory
5. Update edge-react-gui's `package.json` to reference the local file:
   ```json
   "edge-core-js": "./edge-core-js-2.38.4-20260202T0406.tgz"
   ```

Repeat for all dependency repos mentioned in the prompt.
