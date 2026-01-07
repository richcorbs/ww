#!/usr/bin/env bash
# Two-letter abbreviation generation and management

# Generate a simple hash for a file path
hash_filepath() {
  local filepath="$1"
  # Use cksum for a simple, portable hash
  echo -n "$filepath" | cksum | awk '{print $1}'
}

# Convert hash to two-letter code
hash_to_letters() {
  local hash=$1
  # 676 possible combinations (aa-zz)
  local index=$((hash % 676))
  local first=$((index / 26))
  local second=$((index % 26))

  # Convert to letters (a=0, z=25)
  printf "%c%c" $((first + 97)) $((second + 97))
}

# Read abbreviations file
read_abbreviations() {
  local repo_root
  repo_root=$(get_repo_root)

  if [[ ! -f "${repo_root}/${ABBREV_FILE}" ]]; then
    echo '{}'
    return
  fi

  cat "${repo_root}/${ABBREV_FILE}"
}

# Write abbreviations file
write_abbreviations() {
  local data="$1"
  local repo_root
  repo_root=$(get_repo_root)

  echo "$data" | jq '.' > "${repo_root}/${ABBREV_FILE}"
}

# Get abbreviation for a file
get_abbreviation() {
  local filepath="$1"
  local abbrevs
  abbrevs=$(read_abbreviations)

  echo "$abbrevs" | jq -r --arg fp "$filepath" '.[$fp] // empty'
}

# Get filepath from abbreviation
get_filepath_from_abbrev() {
  local abbrev="$1"
  local abbrevs
  abbrevs=$(read_abbreviations)

  echo "$abbrevs" | jq -r --arg ab "$abbrev" \
    'to_entries[] | select(.value == $ab) | .key'
}

# Check if abbreviation is used
is_abbrev_used() {
  local abbrev="$1"
  local abbrevs
  abbrevs=$(read_abbreviations)

  local count
  count=$(echo "$abbrevs" | jq -r --arg ab "$abbrev" \
    '[.[] | select(. == $ab)] | length')

  [[ "$count" -gt 0 ]]
}

# Find next available abbreviation
find_next_abbrev() {
  local start_abbrev="$1"

  # Convert to numeric index
  local first=${start_abbrev:0:1}
  local second=${start_abbrev:1:1}
  local index=$(( ($(printf '%d' "'$first") - 97) * 26 + ($(printf '%d' "'$second") - 97) ))

  # Try next 676 abbreviations (wrap around)
  for ((i=1; i<=676; i++)); do
    local next_index=$(( (index + i) % 676 ))
    local next_first=$((next_index / 26))
    local next_second=$((next_index % 26))
    local next_abbrev
    next_abbrev=$(printf "%c%c" $((next_first + 97)) $((next_second + 97)))

    if ! is_abbrev_used "$next_abbrev"; then
      echo "$next_abbrev"
      return
    fi
  done

  # Should never happen unless all 676 are used
  error "No available abbreviations (all 676 are in use!)"
}

# Generate abbreviation for a file
generate_abbreviation() {
  local filepath="$1"

  # Check if already exists
  local existing
  existing=$(get_abbreviation "$filepath")
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi

  # Generate from hash
  local hash
  hash=$(hash_filepath "$filepath")
  local abbrev
  abbrev=$(hash_to_letters "$hash")

  # Check for collision
  if is_abbrev_used "$abbrev"; then
    abbrev=$(find_next_abbrev "$abbrev")
  fi

  echo "$abbrev"
}

# Set abbreviation for a file
set_abbreviation() {
  local filepath="$1"
  local abbrev="$2"

  local abbrevs
  abbrevs=$(read_abbreviations)

  abbrevs=$(echo "$abbrevs" | jq --arg fp "$filepath" --arg ab "$abbrev" \
    '.[$fp] = $ab')

  write_abbreviations "$abbrevs"
}

# Remove abbreviation for a file
remove_abbreviation() {
  local filepath="$1"

  local abbrevs
  abbrevs=$(read_abbreviations)

  abbrevs=$(echo "$abbrevs" | jq --arg fp "$filepath" 'del(.[$fp])')

  write_abbreviations "$abbrevs"
}

# Clear all abbreviations
clear_abbreviations() {
  write_abbreviations '{}'
}

# Generate and cache abbreviations for a list of files
generate_abbreviations_for_files() {
  local files=("$@")

  # Clear existing abbreviations
  clear_abbreviations

  for file in "${files[@]}"; do
    local abbrev
    abbrev=$(generate_abbreviation "$file")
    set_abbreviation "$file" "$abbrev"
  done
}
