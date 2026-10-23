# Matatu Empire task runner. Run `just` to see every command.

set shell := ["bash", "-euo", "pipefail", "-c"]

project := "default.project.json"
place := "MatatuEmpire.rbxl"
sourcemap := "sourcemap.json"
types_dir := ".luau-lsp"
roblox_types := types_dir / "globalTypes.d.luau"
roblox_types_url := "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

# List all commands
default:
    @just --list --unsorted

# Install the toolchain from rokit.toml (rojo, selene, stylua, luau-lsp, lune, just)
install:
    rokit install

# Install the Rojo plugin into Roblox Studio (restart Studio afterwards)
plugin:
    rojo plugin install

# Live-sync src/ into Studio; then click Rojo -> Connect in Studio
serve:
    rojo serve {{ project }}

# Build a fresh place file you can open in Studio or share
build:
    rojo build {{ project }} -o {{ place }}

# Write sourcemap.json so luau-lsp can follow requires between files
sourcemap:
    rojo sourcemap {{ project }} -o {{ sourcemap }}

# Download the Roblox API type definitions used by `just check`
types:
    mkdir -p {{ types_dir }}
    curl -fsSL {{ roblox_types_url }} -o {{ roblox_types }}

# Type-check every script in strict mode with luau-lsp
check: sourcemap
    @[ -f {{ roblox_types }} ] || just types
    luau-lsp analyze --sourcemap={{ sourcemap }} --definitions={{ roblox_types }} src

# Lint with selene
lint:
    selene src

# Format all Luau code with StyLua
fmt:
    stylua src

# Fail if any Luau file is not formatted (for CI)
fmt-check:
    stylua --check src

# Run the unit tests (driving model, Nairobi map) with Lune
test:
    lune run tests/DriveModel.spec.luau
    lune run tests/World.spec.luau

# Run every check: formatting, lint, types and tests
ci: fmt-check lint check test

# Regenerate the matatu mesh in assets/ (needs python3 with numpy)
mesh:
    python3 tools/make_matatu_mesh.py assets

# Remove generated files (built place, sourcemap, cached type definitions)
clean:
    rm -rf {{ place }} {{ sourcemap }} {{ types_dir }}
