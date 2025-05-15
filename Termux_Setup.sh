#!/bin/bash

###############################################################################
# Script for SSH & GPG Key Management and GitHub Setup on Termux
#
# - Updates packages, installs essentials (vim, git, openssh, gnupg, etc.)
# - Generates SSH and GPG keys, configures Git for secure GitHub use.
# - Offers backup/restore of keys, and outputs public keys for GitHub.
# - Author: Díwash Neupane (Diwash0007)
# - Version: generic:1.3
# - Date: 20231225, Last refined: 2025-05-15
###############################################################################

set -euo pipefail

# Print error message and exit
error_exit() {
  echo "❌ Error: $1"
  exit 1
}

# Ask for input with prompt and store in variable
ask() {
  local prompt="$1"
  local varname="$2"
  local input
  read -rp "$prompt: " input
  eval "$varname=\"\$input\""
}

# Prompt for GitHub username and email with validation (NO DEFAULTS)
get_github_identity() {
  # Ask for username, require non-empty and valid input
  while true; do
    ask "-- Enter your GitHub username" username
    if [[ "$username" =~ ^[a-zA-Z0-9-]{1,39}$ ]]; then
      break
    else
      echo "❗ Invalid GitHub username. It must be 1-39 characters: letters, numbers, hyphens."
    fi
  done

  # Ask for email, require non-empty and basic email validation
  while true; do
    ask "-- Enter your GitHub email address" user_email
    if [[ "$user_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      break
    else
      echo "❗ Invalid email address format. Please try again."
    fi
  done
}

update_environment() {
  echo "🔄 Updating package lists ..."
  pkg update -y || error_exit "Failed to update packages."
  pkg upgrade -y || error_exit "Failed to upgrade packages."
}

install_packages() {
  echo "📦 Installing required packages: git openssh gnupg $extra_packages ..."
  pkg install -y git openssh gnupg $extra_packages || error_exit "Package install failed."
  echo "✅ Required packages installed."
}

generate_an_ssh_key() {
  echo "🔑 Checking for existing SSH key ..."
  mkdir -p ~/.ssh
  if [[ -f ~/.ssh/id_rsa ]]; then
    ask "-- SSH key already exists. Overwrite? (y/N)" overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
      rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
    else
      echo "-- Skipping SSH key generation."
      return
    fi
  fi

  ssh-keygen -t rsa -b 4096 -C "$user_email" -f ~/.ssh/id_rsa -N "" || error_exit "SSH key generation failed."
  eval "$(ssh-agent -s)" || error_exit "Failed to start ssh-agent."
  ssh-add ~/.ssh/id_rsa || error_exit "Failed to add SSH key to agent."
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_rsa
  chmod 644 ~/.ssh/id_rsa.pub
  echo "✅ SSH key generated and added to ssh-agent."
}

generate_a_gpg_key() {
  echo "🔐 Checking for existing GPG key ..."
  if gpg --list-secret-keys --keyid-format=long | grep -q sec; then
    ask "-- GPG key already exists. Generate new one? (y/N)" gen_new
    if [[ "$gen_new" =~ ^[Yy]$ ]]; then
      echo "-- Generating new GPG key ..."
      gpg --full-generate-key || error_exit "GPG key generation failed."
    else
      echo "-- Skipping GPG key generation."
    fi
  else
    gpg --full-generate-key || error_exit "GPG key generation failed."
  fi

  gpg --list-secret-keys --keyid-format=long
  ask "-- Enter your GPG key ID (from above)" gpg_key_id
  gpg --armor --export "$gpg_key_id" > ~/.gnupg/id_gpg || error_exit "Failed to export GPG public key."
  git config --global commit.gpgsign true
  git config --global user.signingkey "$gpg_key_id"
  echo "✅ GPG key exported and Git configured for GPG signing."
}

config_git_and_gpg_key() {
  echo "⚙️ Configuring Git settings ..."
  git config --global user.email "$user_email" || error_exit "Failed to set git user.email"
  git config --global user.name "$username" || error_exit "Failed to set git user.name"
  grep -q "export GPG_TTY" ~/.bashrc 2>/dev/null || echo -e '# Set `GPG_TTY` for GPG\nexport GPG_TTY=$(tty)' >> ~/.bashrc
  source ~/.bashrc
  echo "✅ Git and environment configured."
}

show_ssh_and_gpg_public_keys() {
  echo "------------------------------------------"
  echo "-- Your SSH public key (add this to GitHub):"
  echo "------------------------------------------"
  if [[ -f ~/.ssh/id_rsa.pub ]]; then
    cat ~/.ssh/id_rsa.pub
  else
    echo "⚠️ SSH public key not found!"
  fi
  echo ""
  echo "------------------------------------------"
  echo "-- Your GPG public key (add this to GitHub):"
  echo "------------------------------------------"
  if [[ -f ~/.gnupg/id_gpg ]]; then
    cat ~/.gnupg/id_gpg
    rm -f ~/.gnupg/id_gpg
  else
    echo "⚠️ GPG public key export not found!"
  fi
}

backup_gpg_key() {
  echo "🗄️ Backing up GPG key ..."
  if ! gpg --list-secret-keys | grep -q "$user_email"; then
    echo "⚠️ No GPG key found for $user_email."
    return
  fi
  gpg --export --export-options backup --output ~/id_gpg_public "$user_email" || error_exit "Failed to backup GPG public key."
  gpg --export-secret-keys --export-options backup --output ~/id_gpg_private "$user_email" || error_exit "Failed to backup GPG private key."
  gpg --export-ownertrust > ~/gpg_ownertrust || error_exit "Failed to export GPG ownertrust."
  echo "✅ GPG key backup completed: ~/id_gpg_public ~/id_gpg_private ~/gpg_ownertrust"
}

backup_ssh_key() {
  echo "🗄️ Backing up SSH key ..."
  if [[ -f ~/.ssh/id_rsa && -f ~/.ssh/id_rsa.pub ]]; then
    cp ~/.ssh/id_rsa ~/.ssh/id_rsa.pub ~/
    echo "✅ SSH key backed up to ~/"
  else
    echo "⚠️ No existing SSH key found."
  fi
}

restore_gpg_key() {
  echo "♻️ Restoring GPG key ..."
  pkg install -y gnupg
  [[ -f ~/id_gpg_public ]] && gpg --import ~/id_gpg_public
  [[ -f ~/id_gpg_private ]] && gpg --import ~/id_gpg_private
  [[ -f ~/gpg_ownertrust ]] && gpg --import-ownertrust ~/gpg_ownertrust
  gpg --list-secret-keys --keyid-format=long
  ask "-- Enter your GPG key ID (restored)" gpg_key_id
  git config --global commit.gpgsign true
  git config --global user.signingkey "$gpg_key_id"
  echo "✅ GPG key restored and Git configured."
}

restore_ssh_key() {
  echo "♻️ Restoring SSH key ..."
  if [[ -f ~/id_rsa && -f ~/id_rsa.pub ]]; then
    mkdir -p ~/.ssh
    mv -f ~/id_rsa ~/id_rsa.pub ~/.ssh/
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
    eval "$(ssh-agent -s)" || error_exit "Failed to start ssh-agent."
    ssh-add ~/.ssh/id_rsa || error_exit "Failed to add SSH key to agent."
    echo "✅ SSH key restored."
  else
    echo "⚠️ No SSH key backup files found in ~/"
  fi
}

main_menu() {
  echo "=============================================="
  echo "  SSH & GPG Key Management and GitHub Setup"
  echo "=============================================="
  echo "Select an option:"
  echo "  1) Back up SSH key"
  echo "  2) Back up GPG key"
  echo "  3) Restore SSH key"
  echo "  4) Restore GPG key"
  echo "  5) Fresh setup (update & install only)"
  echo "  6) Fresh setup + generate SSH & GPG keys"
  echo "  7) Exit"
  ask "-- Enter your choice (1-7)" answer
  case "$answer" in
    1) backup_ssh_key ;;
    2) backup_gpg_key ;;
    3) restore_ssh_key ;;
    4) restore_gpg_key; config_git_and_gpg_key ;;
    5) update_environment; install_packages ;;
    6)
      update_environment
      install_packages
      generate_an_ssh_key
      generate_a_gpg_key
      config_git_and_gpg_key
      show_ssh_and_gpg_public_keys
      echo "-- Now, you can copy your SSH and GPG public keys and add them to your GitHub account."
      ;;
    7) echo "👋 Exiting. Goodbye!"; exit 0 ;;
    *) echo "❗ Invalid choice. Try again."; main_menu ;;
  esac
}

# --- main() ---
main() {
  local SCRIPT_VERSION="20230803"
  echo "🚀 $0, v$SCRIPT_VERSION"
  get_github_identity
  ask "-- Do you want to install any other packages (Y/n)" input
  input="${input:-n}"  # Default to 'n' if empty or unset
  if [[ "$input" =~ ^[Yy]$ ]]; then
    ask "-- Enter the name(s) of the package(s) you want to install (space-separated)" package_name
    extra_packages="vim $package_name"
  else
    extra_packages="vim"
  fi
  while true; do
    main_menu
    echo ""
    ask "Would you like to perform another operation? (Y/n)" again
    again="${again:-n}"
    [[ "$again" =~ ^[Nn]$ ]] && break
  done
  echo "✅ All done. Have a great day!"
}
main
