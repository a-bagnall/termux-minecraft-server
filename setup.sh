#!/data/data/com.termux/files/usr/bin/bash
# One-command Minecraft Java server setup/launcher for Termux.
# Default: latest stable Java Edition release, server data in ~/mc.
# Override with MC_VERSION=26.3, MC_SERVER_DIR=~/somewhere, MC_MAX_RAM=3G, etc.

set -Eeuo pipefail

say()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "${PREFIX:-}" && -d "$PREFIX" ]] || die "This script must be run inside Termux."
command -v pkg >/dev/null 2>&1 || die "Termux 'pkg' command not found."

MC_VERSION="${MC_VERSION:-latest}"
SERVER_DIR="${MC_SERVER_DIR:-$HOME/mc}"
MIN_RAM="${MC_MIN_RAM:-1G}"
MAX_RAM="${MC_MAX_RAM:-2G}"

# Download helpers and JSON/checksum tools. These are Termux packages.
say "Updating Termux packages and installing prerequisites"
pkg update -y
pkg install -y curl jq coreutils

WORK_DIR="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/mc-server-setup.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

MANIFEST="$WORK_DIR/version_manifest_v2.json"
say "Reading Mojang's official version manifest"
curl -fsSL --retry 3 --retry-delay 2 \
  "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" \
  -o "$MANIFEST"

LATEST_RELEASE="$(jq -r '.latest.release // empty' "$MANIFEST")"
[[ -n "$LATEST_RELEASE" ]] || die "Could not read the latest stable release from Mojang's manifest."

if [[ "$MC_VERSION" == "latest" ]]; then
  TARGET_VERSION="$LATEST_RELEASE"
else
  TARGET_VERSION="$MC_VERSION"
fi

VERSION_URL="$(jq -r --arg version "$TARGET_VERSION" '.versions[] | select(.id == $version) | .url' "$MANIFEST" | head -n 1)"
[[ -n "$VERSION_URL" && "$VERSION_URL" != "null" ]] || die "Minecraft version '$TARGET_VERSION' was not found in Mojang's official manifest."

VERSION_JSON="$WORK_DIR/version.json"
curl -fsSL --retry 3 --retry-delay 2 "$VERSION_URL" -o "$VERSION_JSON"

JAVA_MAJOR="$(jq -r '.javaVersion.majorVersion // empty' "$VERSION_JSON")"
SERVER_URL="$(jq -r '.downloads.server.url // empty' "$VERSION_JSON")"
SERVER_SHA1="$(jq -r '.downloads.server.sha1 // empty' "$VERSION_JSON" | tr '[:upper:]' '[:lower:]')"
[[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]] || die "Mojang's metadata did not specify a valid Java version for $TARGET_VERSION."
[[ -n "$SERVER_URL" && "$SERVER_URL" != "null" ]] || die "Mojang does not list a vanilla server JAR for $TARGET_VERSION."
[[ "$SERVER_SHA1" =~ ^[a-f0-9]{40}$ ]] || die "Mojang's metadata did not provide a valid server SHA-1 checksum."

say "Minecraft Java $TARGET_VERSION requires Java $JAVA_MAJOR"

# Use the version-specific Termux JDK path. This avoids accidentally launching
# an older Java version through Termux's generic 'java' alternative.
JAVA="$PREFIX/lib/jvm/java-${JAVA_MAJOR}-openjdk/bin/java"
if [[ ! -x "$JAVA" ]]; then
  say "Installing Termux OpenJDK $JAVA_MAJOR"
  pkg install -y "openjdk-${JAVA_MAJOR}"
fi
[[ -x "$JAVA" ]] || die "Java $JAVA_MAJOR was not found at $JAVA after package installation. Check that your Termux repository supports openjdk-${JAVA_MAJOR}."

JAVA_VERSION_LINE="$("$JAVA" -version 2>&1 | head -n 1)"
[[ "$JAVA_VERSION_LINE" == *"\"${JAVA_MAJOR}."* || "$JAVA_VERSION_LINE" == *"\"${JAVA_MAJOR}\""* ]] || \
  die "Expected Java $JAVA_MAJOR, but the selected executable reported: $JAVA_VERSION_LINE"

say "Preparing server directory: $SERVER_DIR"
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

SERVER_JAR="$SERVER_DIR/server.jar"
CURRENT_SHA1=""
if [[ -f "$SERVER_JAR" ]]; then
  CURRENT_SHA1="$(sha1sum "$SERVER_JAR" | awk '{print tolower($1)}')"
fi

if [[ "$CURRENT_SHA1" == "$SERVER_SHA1" ]]; then
  say "server.jar is already the correct Mojang build for $TARGET_VERSION; keeping it"
else
  if [[ -f "$SERVER_JAR" && -d "$SERVER_DIR/world" ]]; then
    printf '\nExisting world detected. Replacing the server JAR may upgrade its world format.\n'
    printf 'Back up your world folder before proceeding if you need a rollback.\n'
    if [[ ! -t 0 ]]; then
      die "Refusing to replace an existing server JAR non-interactively when a world is present."
    fi
    read -r -p "Type UPDATE to replace the server JAR with Minecraft $TARGET_VERSION: " UPDATE_REPLY
    [[ "$UPDATE_REPLY" == "UPDATE" ]] || die "Update cancelled; existing server files were left untouched."
  fi

  say "Downloading official Minecraft $TARGET_VERSION server JAR"
  NEW_JAR="$SERVER_DIR/server.jar.download"
  rm -f "$NEW_JAR"
  curl -fL --retry 3 --retry-delay 2 "$SERVER_URL" -o "$NEW_JAR"
  DOWNLOADED_SHA1="$(sha1sum "$NEW_JAR" | awk '{print tolower($1)}')"
  [[ "$DOWNLOADED_SHA1" == "$SERVER_SHA1" ]] || {
    rm -f "$NEW_JAR"
    die "Server JAR checksum mismatch. The existing server.jar has been left untouched."
  }

  if [[ -f "$SERVER_JAR" ]]; then
    BACKUP="$SERVER_DIR/server.jar.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p "$SERVER_JAR" "$BACKUP"
    say "Previous server JAR backed up to: $BACKUP"
  fi
  mv "$NEW_JAR" "$SERVER_JAR"
  say "Downloaded JAR checksum verified against Mojang's metadata"
fi

# Create defaults only on first setup; never overwrite an existing config.
if [[ ! -f "$SERVER_DIR/server.properties" ]]; then
  say "Creating default server.properties"
  cat > "$SERVER_DIR/server.properties" <<'PROPERTIES'
# Created by termux-minecraft-server.sh. Existing files are never overwritten.
server-port=25565
server-ip=
online-mode=true
white-list=true
enforce-whitelist=true
max-players=10
view-distance=8
simulation-distance=6
level-name=world
motd=Termux Minecraft Server
PROPERTIES
fi

# Minecraft requires an explicit EULA acceptance by the server owner.
if [[ ! -f "$SERVER_DIR/eula.txt" ]] || ! grep -qE '^eula=true([[:space:]]*)$' "$SERVER_DIR/eula.txt"; then
  printf '\nMinecraft EULA: https://aka.ms/MinecraftEULA\n'
  printf 'You must review and accept the EULA before running the server.\n'
  if [[ ! -t 0 ]]; then
    die "No interactive terminal available for EULA acceptance. Run this script directly in Termux."
  fi
  read -r -p "Do you agree to the Minecraft EULA? Type yes to continue: " EULA_REPLY
  [[ "${EULA_REPLY,,}" == "yes" ]] || die "EULA was not accepted; server not started."
  printf 'eula=true\n' > "$SERVER_DIR/eula.txt"
fi

say "Starting Minecraft Java $TARGET_VERSION"
printf 'Server directory: %s\n' "$SERVER_DIR"
printf 'Java: %s\n' "$JAVA_VERSION_LINE"
printf 'Memory: -Xms%s -Xmx%s\n' "$MIN_RAM" "$MAX_RAM"
printf 'Port: 25565 (server-ip is blank so Tailscale/LAN interfaces can connect)\n'
printf '\nWhitelist is enabled. At the server console, add players with:\n'
printf '  whitelist add <MinecraftJavaUsername>\n'
printf '  op <YourMinecraftJavaUsername>\n\n'
printf 'Stop the server safely by entering: stop\n\n'

cd "$SERVER_DIR"
cleanup
trap - EXIT
exec "$JAVA" "-Xms${MIN_RAM}" "-Xmx${MAX_RAM}" -jar "$SERVER_JAR" nogui
