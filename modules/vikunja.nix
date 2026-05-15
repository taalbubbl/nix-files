{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let

  # Default values
  vikunjaDefaults = {
    url = "vikunja.taaltaak.org";
    db_path = "/var/lib/vikunja/vikunja.db";
    files_path = "/var/lib/vikunja/files";
    port = 3456;
  };
  patchedConfigPath = "/var/lib/vikunja/config.patched.yaml";
  cfg = config.vikunja // vikunjaDefaults;


in {
  options.vikunja = {
    enable = mkEnableOption "Enable Vikunja";
    service_jwtsecret = mkOption {
      type = types.str;
    };
    package = mkPackageOption pkgs "vikunja" { };
    url = mkOption {
      type = types.str;
    };
    db_path = mkOption {
      type = types.str;
    };
    files_path = mkOption {
      type = types.str;
    };
    port = mkOption {
      type = types.port;
      default = 3456;
    };
    secretConfigFile = mkOption {
      type = types.path;
      default = config.sops.secrets.vikunja-config.path;
      description = "Path to the decrypted agenix config.yaml file.";
    };
  };

  config = mkIf cfg.enable {
    services.nginx = {
      virtualHosts."${cfg.url}" = {
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 5000M;
              proxy_read_timeout   600s;
              proxy_send_timeout   600s;
              send_timeout         600s;
            '';
          };
      };
    };

    services.vikunja = {
      enable = true;
      port = cfg.port;
      frontendScheme = "http";
      frontendHostname = cfg.url;

      #environmentFiles = [config.age.secrets.vikunja-config.path];

      database = {
        type = "sqlite";
        path = cfg.db_path;
      };

      settings = {
        service = {
        # If enabled, Vikunja will send an email to everyone who is either 
        # assigned to a task or created it when a task reminder is due.
        enableemailreminders = false;
        # Whether to let new users registering themselves or not
        enableregistration = false;
        # The maximum size clients will be able to request for user avatars.
        # If clients request a size bigger than this, it will be changed on the fly.
        maxavatarsize = 4096;
        # The duration of the issued JWT tokens in seconds.
        jwtttl = 2592000;
        # The duration of the "remember me" time in seconds. When the login request is
        # made with the long param set, the token returned will be valid for this period.
        jwtttllong = 25920000;
        maxitemsperpage = 100;
        # JWTsecret gets incerted by environment file
        jwtsecret = {
          file = config.sops.secrets.vikunja-jwt.path;
        };
        };
        #Configure openid
        auth = {
          local.enabled = false;
          openid = {
            enabled = true;
           providers = {
            # The key 'authelia' determines the redirect URI: /auth/openid/authelia
            authelia = {
              name = "Authelia";
              authurl = "https://auth.davidwild.ch";
              logouturl = "https://auth.davidwild.ch/logout";
              clientid = "vikunja";
              clientsecret = {
                file = config.sops.secrets.vikunja-client-secret.path;
              };
            };
          };
          };
        };
      };
    };
    networking.firewall.allowedTCPPorts = [cfg.port];
     
    systemd.services.vikunja = {
  # ... existing code ...

  serviceConfig = {
    Type = "simple";
    DynamicUser = true;
    
    # 1. Add this line:
    SupplementaryGroups = [ "keys" ];

    # 2. To ensure the secret is actually there when the service starts:
    # RequiresMountsFor = [ "/run/agenix" ];

    StateDirectory = "vikunja";
    ExecStart = "${cfg.package}/bin/vikunja";
    Restart = "always";
    
  };
};
  };
}
