#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pterodactyl-installer' - Upgrade Panel Script                             #
#                                                                                    #
# Copyright (C) 2018 - 2026, Always Codex, <info@alwayscodex.my.id>                  #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/BAWORBAWORID/pterodactyl-installer2/blob/master/LICENSE          #
#                                                                                    #
# This script is not associated with the official Pterodactyl Project.               #
# https://github.com/BAWORBAWORID/pterodactyl-installer                              #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

UPGRADE_REPO="BAWORBAWORID/panel"
UPGRADE_BRANCH="master"
PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/var/www/pterodactyl-backup-$(date +%Y%m%d%H%M%S)"

# -------------- Visual Functions -------------- #

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

output() {
  echo -e "* $1"
}

success() {
  echo ""
  output "${COLOR_GREEN}SUCCESS${COLOR_NC}: $1"
  echo ""
}

error() {
  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1" 1>&2
  echo ""
}

warning() {
  echo ""
  output "${COLOR_YELLOW}WARNING${COLOR_NC}: $1"
  echo ""
}

# --------------- Main Functions --------------- #

check_panel_exists() {
  if [ ! -d "$PANEL_DIR" ]; then
    error "Panel directory not found at $PANEL_DIR. Please install the panel first."
    exit 1
  fi
}

backup_panel() {
  output "Creating backup of current panel..."
  output "Backup location: $BACKUP_DIR"

  if [ -d "$BACKUP_DIR" ]; then
    error "Backup directory already exists!"
    exit 1
  fi

  cp -a "$PANEL_DIR" "$BACKUP_DIR"
  success "Backup created successfully"
}

download_upgrade() {
  local temp_dir="/tmp/panel-upgrade-$$"
  
  output "Downloading latest panel from BAWORBAWORID/panel..."
  output "Repository: https://github.com/$UPGRADE_REPO"
  output "Branch: $UPGRADE_BRANCH"

  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"

  cd "$temp_dir"
  curl -sSL "https://github.com/$UPGRADE_REPO/archive/refs/heads/$UPGRADE_BRANCH.tar.gz" | tar xz --strip-components=1

  if [ ! -f "artisan" ]; then
    error "Downloaded files do not appear to be a valid Pterodactyl panel."
    rm -rf "$temp_dir"
    exit 1
  fi

  success "Download completed"
  echo "$temp_dir"
}

upgrade_panel() {
  local source_dir="$1"

  output "Starting panel upgrade..."

  # Put panel into maintenance mode
  cd "$PANEL_DIR"
  php artisan down || true

  # Copy new files
  output "Copying new files..."
  rsync -a --exclude='.git' --exclude='storage' --exclude='.env' "$source_dir/" "$PANEL_DIR/"

  # Set proper permissions
  output "Setting permissions..."
  chown -R www-data:www-data "$PANEL_DIR"
  chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

  # Install PHP dependencies
  output "Installing PHP dependencies..."
  cd "$PANEL_DIR"
  composer install --no-dev --optimize-autoloader --no-interaction

  # Clear and cache config
  output "Clearing and rebuilding caches..."
  php artisan config:clear
  php artisan cache:clear
  php artisan route:clear
  php artisan view:clear
  php artisan config:cache
  php artisan route:cache
  php artisan view:cache

  # Run database migrations
  output "Running database migrations..."
  php artisan migrate --seed --force

  # Set permissions again
  output "Finalizing permissions..."
  chown -R nginx:nginx "$PANEL_DIR" 2>/dev/null || chown -R www-data:www-data "$PANEL_DIR"

  # Bring panel back up
  php artisan up || true

  success "Panel upgrade completed successfully!"
}

cleanup() {
  local source_dir="$1"
  output "Cleaning up temporary files..."
  rm -rf "$source_dir"
}

rollback() {
  output "Rolling back to previous version..."
  
  if [ ! -d "$BACKUP_DIR" ]; then
    error "No backup found. Cannot rollback."
    exit 1
  fi

  cd "$PANEL_DIR"
  php artisan down || true

  rm -rf "$PANEL_DIR"
  cp -a "$BACKUP_DIR" "$PANEL_DIR"

  chown -R www-data:www-data "$PANEL_DIR"
  
  php artisan up || true

  success "Rollback completed"
}

# ------------------ Main ------------------ #

main() {
  print_brake 70
  output "Panel Upgrade Script - Powered by Always Codex"
  output "Upgrade Source: https://github.com/$UPGRADE_REPO"
  print_brake 70
  echo ""

  check_panel_exists

  output "This script will upgrade your Pterodactyl Panel to the latest version from"
  output "BAWORBAWORID/panel repository."
  output ""
  warning "IMPORTANT: Make sure you have a backup before proceeding!"
  output ""

  echo -e -n "* Do you want to proceed with the upgrade? (y/N): "
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ [Yy] ]]; then
    error "Upgrade aborted."
    exit 1
  fi

  # Create backup
  backup_panel

  output ""
  echo -e -n "* Do you want to continue with the upgrade? (y/N): "
  read -r CONFIRM2
  if [[ ! "$CONFIRM2" =~ [Yy] ]]; then
    output "Upgrade cancelled. Backup is available at: $BACKUP_DIR"
    exit 0
  fi

  # Download upgrade
  local temp_dir
  temp_dir=$(download_upgrade)

  # Perform upgrade
  upgrade_panel "$temp_dir"

  # Cleanup
  cleanup "$temp_dir"

  print_brake 70
  output "Upgrade completed! Your panel is now running the latest version."
  output "If you experience any issues, you can rollback using the backup at: $BACKUP_DIR"
  print_brake 70
  echo ""
  output "Powered By Always Codex - https://alwayscodex.my.id"
}

# Run the script
main
