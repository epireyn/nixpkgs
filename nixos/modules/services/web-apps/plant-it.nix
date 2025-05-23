{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.plant-it;
  settingsFormat = pkgs.formats.javaProperties { };
  configFile = settingsFormat.generate "server.properties" (
    {
      spring = {
        datasource = {
          inherit (cfg.database) username url;
        };
        cache = {
          type = if cfg.cache.enable then "redis" else "none";
          redis = {
            inherit (cfg.cache) time-to-live;
          };
        };
        data.redis = {
          inherit (cfg.cache) host port username;
        };
      };
    }
    // cfg.settings
  );
  enableWebEngine = cfg.frontend.proxyToApi || cfg.frontend.enable;
in
{
  options.services.plant-it = {
    enable = lib.mkEnableOption "plant it web-app.";
    package = lib.mkPackageOption pkgs "plant-it" { };
    user = lib.mkOption {
      type = lib.types.str;
      default = "plant-it";
      description = "User running this program.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = cfg.user;
      description = "Primary group of the user running this program.";
    };
    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Database host.";
      };
      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "/run/mysql/mysqld";
        description = "Database socket (connect to if database host is \"localhost\").";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "plant-it";
        description = "Database user.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "plant-it";
        description = "Database name.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 3306;
        description = "Database listening port.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "jdbc:mysql://${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}?autoReconnect=true&allowPublicKeyRetrieval=true&useSSL=false${
          lib.optionalString (cfg.database.socketPath != null) "&unix_socket=${cfg.database.socketPath}"
        }";
        description = "Url used to connect to the database.";
      };
      createLocally = lib.mkEnableOption "Create the database and database user locally." // {
        default = true;
      };
    };

    frontend = {
      enable = lib.mkEnableOption "a web-server for the frontend." // {
        default = true;
      };
      engine = lib.mkOption {
        type = lib.types.enum [
          "nginx"
          "caddy"
        ];
        default = "nginx";
        description = "Web-server engine to use.";
        example = "caddy";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "(Virtual) host to bind the frontend to.";
        example = "planti.example.com";
      };
      proxyToApi = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Proxy calls to the API base url to the backend server.";
        example = false;
      };
    };

    cache = {
      enable = lib.mkEnableOption "Redis as a caching system." // {
        default = true;
      };
      createLocally = lib.mkEnableOption "Create Redis cache locally." // {
        default = true;
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Redis host.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis listening port.";
      };
      time-to-live = lib.mkOption {
        type = lib.types.int;
        default = 604800;
        description = "Retention of cache in seconds (defaults to 1 week).";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = cfg.user;
        description = "Redis username.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          jwt.tokenExpirationAfterDays = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Number of days after which JWT tokens expire.";
          };
          server = {
            port = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              description = "Port on which the API is listening.";
            };
            servlet.context-path = lib.mkOption {
              type = lib.types.str;
              default = "/api";
              description = "Base url on which the API is listening.";
            };
          };
          upload.location = lib.mkOption {
            type = lib.types.pathWith {
              inStore = false;
              absolute = true;
            };
            default = "/var/lib/plant-it";
            description = "Location where uploaded pictures are stored.";
          };
        };
      };
      default = { };
      description = ''
        Extra configuration options to append or override.
        For available and default option values see
        [upstream configuration file](https://github.com/MDeLuise/plant-it/blob/main/backend/src/main/resources/application.properties).
      '';
      example = ''
        {
          spring.mail = {
            host = "smtp.gmail.com";
            port = 853;
            username = "no-reply";
            properties.mail.smtp = {
              auth = true;
              starttls.enable = true;
            };
          };

          server.rateLimit.requestPerMinute = 990;
          floracodex.url = "https://api.floracodex.com";
        }
      '';

    };
    secretFile = lib.mkOption {
      type = lib.types.pathWith {
        absolute = true;
        inStore = false;
      };
      example = "/run/secrets/plant-it";
      description = ''
        A Java property file that overrides the config. Mainly used for secrets.
        Properties' names can be found in [upstream configuration file](https://github.com/MDeLuise/plant-it/blob/main/backend/src/main/resources/application.properties). 
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.cache.createLocally && cfg.cache.host == "localhost";
        message = "When services.plant-it.cache.createLocally is enabled, you need to use localhost as a cache server.";
      }
      {
        assertion =
          cfg.database.createLocally && (cfg.database.host == "localhost" && cfg.database.socketPath != null);
        message = "When services.plant-it.database.createLocally is enabled, you need to use localhost as a database server.";
      }
    ];

    services.nginx = lib.mkIf (enableWebEngine && cfg.frontend.engine == "nginx") {
      enable = true;
      virtualHosts.${cfg.frontend.host} = {
        locations = {
          "/" = lib.mkIf cfg.frontend.enable {
            root = "${pkgs.plant-it-frontend}";
            tryFiles = "$uri $uri/ =404";
          };
          ${cfg.settings.server.servlet.context-path} = lib.mkIf cfg.frontend.proxyToApi {
            priority = 1100;
            recommendedProxySettings = true;
            proxyPass = "http://localhost:${toString cfg.settings.server.port}";
            proxyWebsockets = true;
          };
        };
      };
    };

    services.caddy = lib.mkIf (enableWebEngine && cfg.frontend.engine == "caddy") {
      enable = true;
      virtualHosts.${cfg.frontend.host}.extraConfig = ''
        route {
          
          ${lib.optionalString cfg.frontend.proxyToApi ''
             ${cfg.settings.server.servlet.context-path}/* {
               reverse_proxy http://localhost:${toString cfg.settings.server.port}";
            }
          ''}
          ${lib.optionalString cfg.frontend.enable ''
            * {
                         root * ${pkgs.plant-it-frontend}
                         file_server
                      }''}
        }
      '';
    };

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };

    services.mysql = lib.mkIf cfg.database.createLocally {
      enable = true;
      package = lib.mkDefault pkgs.mariadb;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.username;
          ensurePermissions = {
            "${cfg.database.name}.*" = "ALL_PRIVILEGES";
          };
        }
      ];
    };

    services.redis.servers.plant-it = {
      enable = cfg.cache.enable;
      user = cfg.cache.username;
      port = cfg.cache.port;
    };

    systemd = {
      tmpfiles.rules = [
        "d ${cfg.settings.upload.location} 2750 ${cfg.user} ${cfg.group}"
      ];
      services.plant-it = {
        description = "Plant it backend (A selfhosted web-app for plants)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = "/var/lib/${cfg.user}";
          WorkingDirectory = "/var/lib/${cfg.user}";
          ExecStart = "${cfg.package}/bin/plant-it --spring.config.location=${configFile} ${
            lib.optional cfg.secretFile != null "--spring.config.location=${cfg.secretFile}"
          }";
          Restart = "on-failure";
          RestartSec = "5s";

          DeviceAllow = [ "" ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          PrivateDevices = true;
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
        };
      };
    };
  };
}
