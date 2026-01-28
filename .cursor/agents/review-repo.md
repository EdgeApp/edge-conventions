---
name: review-repo
description: Orchestrator that launches repo-specific review subagents. Use when reviewing code from a specific repository.
---

## Context Expected

You will receive:
- Repository name
- Branch name
- PR URL
- Base branch
- Summary of changed files

## Orchestration

Launch the repo-specific subagent for the repository being reviewed. Pass all context you received to the subagent.

If the subagent does not exist, skip it silently.

## Repository to Subagent Mapping

repo: edge-react-gui  subagent: review-edge-react-gui
repo: edge-currency-accountbased  subagent: review-edge-currency-accountbased
repo: edge-core-js  subagent: review-edge-core-js
repo: edge-currency-plugins  subagent: review-edge-currency-plugins
repo: edge-login-ui-rn  subagent: review-edge-login-ui-rn
repo: edge-exchange-plugins  subagent: review-edge-exchange-plugins
repo: edge-currency-monero  subagent: review-edge-currency-monero
repo: edge-login-server  subagent: review-edge-login-server
repo: nymtest  subagent: review-nymtest
repo: react-native-zcash  subagent: review-react-native-zcash

