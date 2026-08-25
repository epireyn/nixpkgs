{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.aurral;
  dataDir = if lib.hasPrefix "/" cfg.dataDir then cfg.dataDir else "/var/lib/${cfg.dataDir}";
in
{
  options.services.aurral = {
    enable = lib.mkEnableOption "aurral";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Aurral package to use";
      default = pkgs.aurral;
    };
    dataDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/var/lib/aurral";
      description = "Config folder of aurral";
    };
    downloadDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${dataDir}/downloads";
      description = "Folder in which aurral will manage downloaded files";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "aurral";
      description = "User owning the process";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "aurral";
      description = "Group owning the process";
    };
    settings = lib.mkOption {
      description = ''
        Additional configuration (environment variables) for Aurral, see
        <https://docs.aurral.org/admin/environment/> for supported values.
      '';

      type = lib.types.submodule {
        freeformType =
          with lib.types;
          attrsOf (oneOf [
            bool
            int
            str
          ]);
        options = {
          PORT = lib.mkOption {
            description = "Port to listen to";
            type = lib.types.port;
            default = 3001;
          };
        };
      };
    };

    environmentFile = lib.mkOption {
      description = "Environment file containing variables for the service configuration (useful to keep secrets out of the store).";
      type = lib.types.nullOr lib.types.path;
      default = null;
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open ports in the firewall for the server.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasAttr "AURRAL_DATA_DIR" cfg.settings);
        message = "Use the option config.services.aurral.dataDir instead of the AURRAL_DATA_DIR setting.";
      }
      {
        assertion = !(lib.hasAttr "DOWNLOAD_FOLDER" cfg.settings);
        message = "Use the option config.services.aurral.downloadDir instead of the DOWNLOAD_FOLDER setting.";
      }
    ];
    systemd = {
      services.aurral = {
        environment = (lib.mapAttrs (_: toString) cfg.settings) // {
          AURRAL_DATA_DIR = dataDir;
          DOWNLOAD_FOLDER = cfg.downloadDir;
        };

        description = "Aurral: A self-hosted music discovery tool";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [
          cfg.package
          pkgs.yt-dlp
        ];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;

          EnvironmentFile = cfg.environmentFile;
          StateDirectory = dataDir;
          WorkingDirectory = dataDir;
          ExecStart = "${lib.getExe cfg.package}";
          Restart = "on-failure";

          ProtectSystem = "strict";
          ReadWritePaths = [
            dataDir
            cfg.downloadDir
          ];
          PrivateTmp = true;
          PrivateDevices = true;
          PrivateIPC = true;
          ProtectHostname = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          LockPersonality = true;
          RestrictSUIDSGID = true;
          ProtectHome = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictRealtime = true;
          SystemCallArchitectures = "native";
          RestrictNamespaces = true;
          RemoveIPC = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          ProtectKernelModules = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ];
          SystemCallFilter = [
            "~@obsolete"
            "~@privileged"
            "~@raw-io"
            "~@resources"
            "~@mount"
            "~@debug"
            "~@cpu-emulation"
          ];
        };
      };

      tmpfiles.settings."10-aurral" = {
        ${cfg.downloadDir}.d = {
          group = cfg.group;
          user = cfg.user;
          mode = "0755";
        };
        ${dataDir}.d = {
          group = cfg.group;
          user = cfg.user;
          mode = "0755";
        };
      };
    };

    users.users = lib.mkIf (cfg.user == "aurral") {
      aurral = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    users.groups = lib.mkIf (cfg.group == "aurral") { aurral = { }; };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.settings.PORT ];
    };
  };

  meta.maintainers = with lib.maintainers; [ epireyn ];
}
