#!/bin/bash
set -e

# =============================================================================
# Update CHANGELOG
# Auto-move [Unreleased] content to versioned section if not exists
# For stable releases: squash beta/prerelease entries into stable version
# Usage: ./update-changelog.sh VERSION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

VERSION="${1:-}"
CHANGELOG="${PROJECT_DIR}/CHANGELOG.md"
TODAY=$(date +%Y-%m-%d)

if [ -z "$VERSION" ]; then
    log_error "Usage: $0 VERSION"
    exit 1
fi

if [ ! -f "$CHANGELOG" ]; then
    log_error "CHANGELOG.md not found"
    exit 1
fi

# Check if version section already exists
if grep -q "## \[${VERSION}\]" "$CHANGELOG"; then
    log_info "CHANGELOG already has section for [${VERSION}]"
    exit 0
fi

# Determine if this is a stable release (no prerelease suffix)
IS_STABLE=false
if [[ ! "$VERSION" =~ -(alpha|beta|rc) ]]; then
    IS_STABLE=true
fi

# Extract base version (e.g., "0.4.3" from "0.4.3-beta-1")
BASE_VERSION=$(echo "$VERSION" | sed -E 's/-(alpha|beta|rc).*//')

# Function to squash beta entries into stable release
squash_prereleases() {
    local base_ver="$1"
    local temp_file=$(mktemp)
    
    # Find all prerelease versions for this base version
    local prerelease_pattern="## \[${base_ver}-(alpha|beta|rc)"
    
    if ! grep -qE "$prerelease_pattern" "$CHANGELOG"; then
        log_info "No prerelease entries found for ${base_ver}"
        return 0
    fi
    
    log_info "Squashing prerelease entries into [${base_ver}]"
    
    # Use awk to:
    # 1. Collect all content from prerelease sections
    # 2. Remove the prerelease section headers
    # 3. Merge content into the stable release section
    awk -v base_ver="$base_ver" '
    BEGIN {
        in_prerelease = 0
        in_stable = 0
        added_content = ""
        fixed_content = ""
        changed_content = ""
        current_category = ""
    }
    
    # Match prerelease version headers
    /^## \[/ && $0 ~ base_ver "-(alpha|beta|rc)" {
        in_prerelease = 1
        next
    }
    
    # Match stable version header
    /^## \[/ && $0 ~ "\\[" base_ver "\\]" && $0 !~ "-(alpha|beta|rc)" {
        in_stable = 1
        print
        next
    }
    
    # Match any other version header - end prerelease/stable section
    /^## \[/ && in_prerelease {
        in_prerelease = 0
    }
    
    # Track categories in prerelease sections
    in_prerelease && /^### Added/ { current_category = "added"; next }
    in_prerelease && /^### Fixed/ { current_category = "fixed"; next }
    in_prerelease && /^### Changed/ { current_category = "changed"; next }
    in_prerelease && /^### / { current_category = "other"; next }
    
    # Collect content from prerelease sections
    in_prerelease && /^- / {
        if (current_category == "added") added_content = added_content $0 "\n"
        else if (current_category == "fixed") fixed_content = fixed_content $0 "\n"
        else if (current_category == "changed") changed_content = changed_content $0 "\n"
        next
    }
    
    # Skip empty lines in prerelease sections
    in_prerelease && /^$/ { next }
    
    # For stable section, inject collected content at appropriate places
    in_stable && /^### Added/ {
        print
        if (added_content != "") {
            print ""
            printf "%s", added_content
        }
        next
    }
    
    in_stable && /^### Fixed/ {
        print
        if (fixed_content != "") {
            print ""
            printf "%s", fixed_content
        }
        next
    }
    
    in_stable && /^### Changed/ {
        print
        if (changed_content != "") {
            print ""
            printf "%s", changed_content
        }
        next
    }
    
    # End stable section on next version
    in_stable && /^## \[/ && $0 !~ base_ver {
        in_stable = 0
    }
    
    # Print all other lines (skip prerelease section lines)
    !in_prerelease { print }
    
    ' "$CHANGELOG" > "$temp_file"
    
    # Remove duplicate entries and clean up
    mv "$temp_file" "$CHANGELOG"
}

# Check if [Unreleased] section has content
UNRELEASED_CONTENT=$(awk '/^## \[Unreleased\]/{flag=1; next} /^## \[/{flag=0} flag' "$CHANGELOG" | grep -v '^$' | head -1)

if [ -z "$UNRELEASED_CONTENT" ]; then
    log_warn "[Unreleased] section is empty. Creating empty version section."
    sed -i '' "s/## \[Unreleased\]/## [Unreleased]\n\n## [${VERSION}] - ${TODAY}/" "$CHANGELOG"
else
    log_info "Moving [Unreleased] content to [${VERSION}] - ${TODAY}"
    sed -i '' "s/## \[Unreleased\]/## [Unreleased]\n\n## [${VERSION}] - ${TODAY}/" "$CHANGELOG"
fi

# For stable releases, squash any existing prerelease entries
if [ "$IS_STABLE" = true ]; then
    squash_prereleases "$BASE_VERSION"
fi

log_info "CHANGELOG updated successfully"
