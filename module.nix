{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.windscribe;
  helperToolsBin = "${cfg.package.helperToolsEnv}/bin";
in
{
  options.programs.windscribe = {
    enable = lib.mkEnableOption "Windscribe VPN client (.deb repack)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The Windscribe package to use.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "fumoctl" ];
      description = "Users added to the windscribe group so the GUI/CLI can talk to windscribe-helper.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to autostart the Windscribe GUI with graphical-session.target.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Bind-mount /opt/windscribe (instead of symlinking) because windscribe-helper validates
    # realpath(exePath) == "/opt/windscribe" before spawning windscribeamneziawg/openvpn/etc.
    system.activationScripts.windscribe-opt = ''
      if [ -L /opt/windscribe ]; then
        rm -f /opt/windscribe
      fi
      mkdir -p /opt/windscribe
      ${pkgs.util-linux}/bin/umount -l /opt/windscribe 2>/dev/null || true
      ${pkgs.util-linux}/bin/mount --bind -o ro ${cfg.package}/opt/windscribe /opt/windscribe
    '';

    environment.etc."windscribe/platform".text = "linux_deb_x64";

    users.groups.windscribe = { };
    users.users = {
      windscribe = {
        description = "Windscribe wstunnel runtime user";
        isSystemUser = true;
        group = "windscribe";
      };
    }
    // lib.genAttrs cfg.users (_: {
      extraGroups = [ "windscribe" ];
    });

    systemd.services.windscribe-helper = {
      description = "Windscribe VPN helper daemon";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-pre.target" ];
      before = [ "network-pre.target" ];
      restartTriggers = [ cfg.package ];
      serviceConfig = {
        Type = "simple";
        Group = "windscribe";
        RuntimeDirectory = "windscribe";
        RuntimeDirectoryMode = "0770";
        StateDirectory = "windscribe";
        LogsDirectory = "windscribe";
        # helper calls setenv("PATH", "/usr/sbin:/usr/bin:/sbin:/bin", 1) in main(),
        # so expose helper tools at /usr/bin and /usr/sbin inside its mount namespace.
        BindReadOnlyPaths = [
          "${cfg.package}/opt/windscribe:/opt/windscribe"
          "${helperToolsBin}:/usr/bin"
          "-${helperToolsBin}:/usr/sbin"
        ];
        ExecStart = "/opt/windscribe/helper";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.user.services.windscribe = lib.mkIf cfg.autoStart {
      description = "Windscribe VPN GUI";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      restartTriggers = [ cfg.package ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --autostart";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
