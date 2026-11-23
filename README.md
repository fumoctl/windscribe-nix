# windscribe-nix

Unofficial NixOS flake that repacks the **official Windscribe Desktop `.deb`** (`x86_64-linux`) from [Windscribe/Desktop-App](https://github.com/Windscribe/Desktop-App/releases).

## Why a `.deb` repack?

Building Windscribe from its public open-source GitHub repo uses `wsnet`'s public `FailoverContainer`, which only includes `api.windscribe.com` and omits Windscribe's private anti-censorship API failover domains. On restrictive networks (e.g., FortiGate / campus firewalls that block `api.windscribe.com`), built-in WireGuard fails to initialize (`WgConfigs/init`).

Repacking the official `.deb` keeps Windscribe's prebuilt `libwsnet.so` (with the full API failover chain), `libssl.so.4`, `libcrypto.so.4`, OpenVPN DCO, AmneziaWG, `ctrld`, `wstunnel`, GUI, and `windscribe-cli`, while patching all binaries and helper scripts for NixOS.

## Usage

### 1. Add the flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    windscribe-nix.url = "github:fumoctl/windscribe-nix";
    # Or pin a specific release tag:
    # windscribe-nix.url = "github:fumoctl/windscribe-nix/v2.25.8";
  };
}
```

### 2. Enable the NixOS module

Make sure unfree packages are allowed (`nixpkgs.config.allowUnfree = true;` or allow `windscribe-bin` in `allowUnfreePredicate`), then import `inputs.windscribe-nix.nixosModules.default`:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.windscribe-nix.nixosModules.default
  ];

  programs.windscribe = {
    enable = true;
    users = [ "your-username" ]; # Adds user to the `windscribe` group for helper IPC
    autoStart = false;           # Set true to start the GUI with graphical-session.target
  };
}
```

### Module options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `programs.windscribe.enable` | `bool` | `false` | Enable Windscribe GUI, CLI, and `windscribe-helper.service`. |
| `programs.windscribe.package` | `package` | `pkgs.callPackage ./package.nix {}` | The Windscribe package to install. |
| `programs.windscribe.users` | `listOf str` | `[]` | Users added to the `windscribe` group so the GUI/CLI can talk to `windscribe-helper`. |
| `programs.windscribe.autoStart` | `bool` | `false` | Autostart the Windscribe GUI via a systemd user service (`graphical-session.target`). |

### What the NixOS module configures

- Installs `windscribe` (GUI) and `windscribe-cli` into `environment.systemPackages`.
- Bind-mounts `/opt/windscribe` from the Nix store package (so `windscribe-helper`'s `realpath("/opt/windscribe")` security check passes).
- Writes `/etc/windscribe/platform` (`linux_deb_x64`).
- Creates the `windscribe` system user/group and enables `windscribe-helper.service`.

## Local build

```bash
nix build
```

## Auto-updates

A GitHub Actions workflow (`.github/workflows/update.yml`) runs daily at `06:00 UTC` (and via manual `workflow_dispatch`):

1. Checks for the latest `Windscribe/Desktop-App` release.
2. Prefetches `windscribe_<version>_amd64.deb` and updates `version` and `hash` in `package.nix`.
3. Runs `nix build` to verify all binaries pass `autoPatchelfHook`.
4. Commits to `main` and publishes a matching GitHub Release (`v<version>`).

## License

The Nix packaging in this repository is MIT-licensed. Windscribe itself is proprietary/unfree software owned by Windscribe Limited.
