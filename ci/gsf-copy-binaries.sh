#!/bin/bash

set -euo pipefail

# Variables
TOOLS=(curl skopeo jq git make)
SOURCE_ORG="digital-asset"
SOURCE_GHCR="ghcr.io/${SOURCE_ORG}"
SOURCE_REPO="decentralized-canton-sync"
SOURCE_TOKEN=$GITHUB_TOKEN
DEST_ORG="canton-foundation"
DEST_GHCR="ghcr.io/${DEST_ORG}"
DEST_REPO=$GITHUB_REPO
DEST_TOKEN=$GITHUB_TOKEN
GITHUB_USERNAME=$GITHUB_ACTOR

missing_tool() {
  local missing_tools=()

  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing_tools+=("$tool")
    fi
  done

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo -e "ERROR: The following tools are missing:\n- ${missing_tools[*]}"
    exit 1
  fi
}

gsf_devnet_version() {
    GSF_DEVNET_VERSION=$(curl -s https://docs.dev.global.canton.network.sync.global/info | jq -r .sv.version)
}

get_images_from_splice() {
  local remote_images_url="https://raw.githubusercontent.com/hyperledger-labs/splice/refs/heads/release-line-${GSF_DEVNET_VERSION}/cluster/images/local.mk"
  local temp_images_file="images.mk"

  # Download the images.mk file
  curl -s -o "$temp_images_file" "$remote_images_url"

  # Clean up the downloaded file
  sed -i '/foreach/d' "$temp_images_file"  # Remove foreach loop
  echo 'print_all_images: $(info $(images))' >> "$temp_images_file" # Add target to print images

  # Extract and process the list of images
  IMAGES=$(
    make -s -f "$temp_images_file" print_all_images |
      tr ' ' '\n' | # Replace spaces with newlines
      sed '/^$/d' | # Remove empty lines
      sed "s%^%${SOURCE_REPO}/docker/%" | # Prefix with source repo path
      egrep -v 'pulumi-kubernetes-operator|splice-test-runner-hook' # Filter out unwanted images
  )

  # Clean up the temporary file
  rm "$temp_images_file"

  # Output the result
  echo "Docker images from splice: $IMAGES"
}

get_helm_from_splice() {
  local remote_helm_url="https://raw.githubusercontent.com/hyperledger-labs/splice/refs/heads/release-line-${GSF_DEVNET_VERSION}/cluster/helm/local.mk"
  local temp_helm_file="helm.mk"

  # Download the helm.mk file
  curl -s -o "$temp_helm_file" "$remote_helm_url"

  # Add target to print charts
  echo 'print_all_charts: $(info $(app_charts))' >> "$temp_helm_file"

  # Extract and process the list of charts
  HELM_CHARTS=$(
    make -s -f "$temp_helm_file" print_all_charts |
      tr ' ' '\n' | # Replace spaces with newlines
      sed '/^$/d' | # Remove empty lines
      sed "s%^%${SOURCE_REPO}/helm/%" # Prefix with source repo path
  )

  # Clean up the temporary file
  rm "$temp_helm_file"

  # Output the result
  echo "Helm charts from splice: $HELM_CHARTS"
}

copy_artifact() {
    local source=$1
    local destination=$2
    shift 2

    if skopeo inspect --raw --creds "${GITHUB_USERNAME}:${DEST_TOKEN}" "docker://${destination}" &>/dev/null; then
        echo "Already present, skipping: ${destination}"
        return
    fi

    skopeo copy --all \
        --retry-times 5 \
        --dest-creds "${GITHUB_USERNAME}:${DEST_TOKEN}" \
        "$@" \
        "docker://${source}" \
        "docker://${destination}"
}

copy_docker_images() {
    for image in $IMAGES; do
        image_trimmed=$(sed 's/.*\///' <<< "$image")
        echo "Copying Docker image: $image:${GSF_DEVNET_VERSION}"
        copy_artifact \
            "${SOURCE_GHCR}/${image}:${GSF_DEVNET_VERSION}" \
            "ghcr.io/${DEST_REPO}/docker/${image_trimmed}:${GSF_DEVNET_VERSION}" \
            --override-os linux \
            --override-arch amd64
    done
}

copy_helm_charts() {
    for chart in $HELM_CHARTS; do
        chart_trimmed=$(sed 's/.*\///' <<< "$chart")
        echo "Copying Helm chart: $chart:${GSF_DEVNET_VERSION}"
        copy_artifact \
            "${SOURCE_GHCR}/${chart}:${GSF_DEVNET_VERSION}" \
            "ghcr.io/${DEST_REPO}/helm/${chart_trimmed}:${GSF_DEVNET_VERSION}"
    done
}

# Execute functions
missing_tool
gsf_devnet_version
get_images_from_splice
get_helm_from_splice
copy_docker_images
copy_helm_charts

echo "Copying completed."