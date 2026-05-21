#!/usr/bin/env bash
set -euo pipefail

swift build
swift test
jq empty llm/manifest.json

while IFS= read -r documented_path; do
  if [[ ! -e "$documented_path" ]]; then
    echo "Missing documented path from llm/manifest.json: $documented_path" >&2
    exit 1
  fi
done < <(jq -r '.entrypoint, .preferredReadOrder[], .docs[].path' llm/manifest.json | sort -u)

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --spec Examples/LLMShowcase/project.yml

  if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild \
      -project Examples/LLMShowcase/LLMShowcase.xcodeproj \
      -scheme LLMShowcase \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO \
      build
  fi
else
  echo "Skipping showcase generation because xcodegen is not installed."
fi
