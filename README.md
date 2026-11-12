# Termux Minecraft Server

A one-command setup script for hosting a vanilla Minecraft Java Edition server on Android using Termux.

## Installation

Install Git and clone the repository:

```bash
pkg install git -y
git clone https://github.com/a-bagnall/termux-minecraft-server.git
cd termux-minecraft-server
```

Run the setup script:

```bash
bash setup.sh
```

The script automatically:
- Installs required dependencies and Java.
- Downloads the latest stable Minecraft server.
- Verifies the server JAR against Mojang's checksum.
- Configures the server and prompts for EULA acceptance.
- Starts the server.

## Configuration

| Setting | Default |
|---|---|
| Minecraft version | Latest stable |
| Server directory | `~/mc` |
| Server port | `25565` |
| Max players | 10 |
| View distance | 8 |
| Simulation distance | 6 |
| Whitelist | Enabled |
| Maximum RAM | 2 GB |

Optional environment variables:

```bash
MC_VERSION=26.3 \
MC_MAX_RAM=4G \
bash setup.sh
```

Available options: `MC_VERSION`, `MC_SERVER_DIR`, `MC_MIN_RAM`, `MC_MAX_RAM`.

## Connecting

Connect using the host device's IP address:

```text
<server-ip>:25565
```

For remote access, connect through Tailscale using the host's Tailscale IP.

Players must use the same Minecraft version as the server.

## Server Management

Run `bash setup.sh` again to start or update the server.

Server files and world data are stored in `~/mc`.

Useful console commands:

| Command | Description |
|---|---|
| `stop` | Safely stop the server |
| `whitelist add <username>` | Allow a player to join |
| `op <username>` | Grant operator permissions |

**Note:** Back up your world before updating Minecraft versions. The script prompts before replacing an existing server JAR when a world is detected.

Custom world imports are not handled by this script.
