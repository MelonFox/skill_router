#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

swift build --product skill-router
binary_directory="$(swift build --show-bin-path)"
SKILL_ROUTER_CLI_SOURCE="$binary_directory/skill-router" swift run SkillRouterApp
