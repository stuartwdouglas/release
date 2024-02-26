#!/bin/bash
# Script to extract GitHub org/repo from the specified payload or latest
# release if no payload is provided. Used for locking down repos that
# come from the release payload.

set -eo pipefail

echo "Generating updated list of repos for acknowledge-critical-fixes-only..."

# Manually added repos (space-separated list)
MANUALLY_ADDED_REPOS="openshift/os"

# Function to display usage
usage() {
    echo "Usage: $0 [PAYLOAD] [OUTPUT_FILE]"
    echo "PAYLOAD: Optional. The payload to process."
    echo "OUTPUT_FILE: Optional. File to write the results to. Default is 'acknowledge-critical-fix-repos.txt'."
}

# Function to fetch the latest release payload
fetch_latest_payload() {
    local releases_json=$(curl -s "https://sippy.dptools.openshift.org/api/releases")
    local latest_release=$(echo "$releases_json" | jq -r '.releases[0]')
    local latest_release_info=$(curl -s "https://amd64.ocp.releases.ci.openshift.org/api/v1/releasestream/$latest_release.0-0.nightly/latest")
    local pull_spec=$(echo "$latest_release_info" | jq -r '.pullSpec')
    echo "$pull_spec"
}

PAYLOAD=${1:-$(fetch_latest_payload)}
OUTPUT_FILE=${2:-$(dirname "${BASH_SOURCE[0]}")/acknowledge-critical-fix-repos.txt} # Default output file

# Check if the payload fetching failed
if [ -z "$PAYLOAD" ]; then
    echo "Error: Failed to fetch the latest release payload."
    exit 1
fi

# Extract and process the information
EXTRACTED_INFO=$(oc adm release info "$PAYLOAD" -o json | jq -r '.references.spec.tags[] | select(.annotations."io.openshift.build.source-location" != "") | .annotations."io.openshift.build.source-location" | capture("https://github.com/(?<org>[^/]+)/(?<repo>[^/]+)") | "\(.org)/\(.repo)"' | sort -u)

# Combine manually added repos with extracted ones and remove duplicates
COMBINED_INFO=$(echo -e "$MANUALLY_ADDED_REPOS\n$EXTRACTED_INFO" | sort -u | sed '/^$/d')

# Check if the extraction was successful
if [ -z "$COMBINED_INFO" ]; then
    echo "Error: Failed to extract or combine information."
    exit 2
fi

# Output the results
echo "# This was generated by ${BASH_SOURCE[0]} on $(date)" > $OUTPUT_FILE
echo "$COMBINED_INFO" >> "$OUTPUT_FILE"
echo "Extracted and manually added GitHub org/repo written to $OUTPUT_FILE"