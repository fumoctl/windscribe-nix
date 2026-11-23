{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.windscribe;
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

    # Windscribe binaries hardcode /opt/windscribe/... and /etc/windscribe/platform
    systemd.tmpfiles.rules = [
      "L+ /opt/windscribe - - - - ${cfg.package}/opt/windscribe"
    ];

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
      serviceConfig = {
        Type = "simple";
        Group = "windscribe";
        RuntimeDirectory = "windscribe";
        RuntimeDirectoryMode = "0770";
        StateDirectory = "windscribe";
        LogsDirectory = "windscribe";
        ExecStart = "${cfg.package}/opt/windscribe/helper";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.user.services.windscribe = lib.mkIf cfg.autoStart {
      description = "Windscribe VPN GUI";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --autostart";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
