#!/bin/bash

# check-svs-majority.sh
# This script checks if the current GSF version is present in at least 2/3 of the SVs.
# It fetches the GSF version from the provided GSF_DOCS URL and compares it against the list of SV versions.
# If the majority condition is met, it sets the SVS_MAJORITY environment variable to "true", otherwise "false".
# The result is written to the GITHUB_OUTPUT file as "svs_majority".
# Expects two arguments:
# 1. GSF_ENV: The environment (e.g., DevNet, TestNet, MainNet).
# 2. GSF_DOCS: The URL to the GSF documentation.
# Usage: ./check-svs-majority.sh <GSF_ENV> <GSF_DOCS_URL>

set -euo pipefail

GSF_ENV=$1
GSF_DOCS=$2
SVS_MAJORITY="false"

log() {
    local level="$1"
    shift
    echo -e "[$level] $*"
}

fatal() {
    log "FATAL" "$1"
    echo "svs_majority=false" >> "$GITHUB_OUTPUT"
    exit 1
}

gsf_version() {
    log "INFO" "Fetching GSF version from: ${GSF_DOCS}/info"
    GSF_VERSION=$(curl -sSf --max-time 5 "${GSF_DOCS}/info" | jq -er '.sv.version') \
        || fatal "Failed to fetch or parse GSF version"
}

check_svs_majority() {
    log "INFO" "Fetching all SV versions from: ${GSF_DOCS}/versions"
    ALL_VERSIONS=$(curl -sSfm5 "${GSF_DOCS}/versions" | \
      awk -F',' 'NR > 1 { gsub(/^ +| +$/, "", $3); print $3 }'
      ) || fatal "Failed to fetch or parse SV version list"
    if [[ -z "$ALL_VERSIONS" ]]; then
        fatal "No SV versions found"
    fi

    SVS_WITH_GSF_VERSION=$(echo "$ALL_VERSIONS" | grep -cxF "$GSF_VERSION") || true
    ALL_VERSIONS_COUNT=$(echo "$ALL_VERSIONS" | wc -l)

    REQUIRED_MAJORITY=$(((ALL_VERSIONS_COUNT + 1) * 2 / 3))

    log "INFO" "GSF ${GSF_ENV} version:             $GSF_VERSION"
    log "INFO" "SVs with GSF version:             $SVS_WITH_GSF_VERSION"
    log "INFO" "SVs needed for 2/3 majority:      $REQUIRED_MAJORITY"
    log "INFO" "Total SVs:                        $ALL_VERSIONS_COUNT"
    log "INFO" "SVs with GSF version percentage:  $((SVS_WITH_GSF_VERSION * 100 / ALL_VERSIONS_COUNT))%"

    if [ "$SVS_WITH_GSF_VERSION" -lt "$REQUIRED_MAJORITY" ]; then
        SVS_MAJORITY="false"
        log "ERROR" "Not enough SVs with GSF version for majority"
    else
        SVS_MAJORITY="true"
        log "INFO" "Enough SVs with GSF version for majority"
    fi
}

gsf_version
check_svs_majority

echo "svs_majority=$SVS_MAJORITY" >> "$GITHUB_OUTPUT"
