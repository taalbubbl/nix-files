{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  autheliaDefaults = {
    domain = "auth.davidwild.ch";
    sessionDomain = "davidwild.ch";
    port = 9091;
  };
  cfg = config.authelia // autheliaDefaults;
in {
  options.authelia = {
    enable = mkEnableOption "Enable Authelia";
    domain = mkOption {
      type = types.str;
      default = autheliaDefaults.domain;
    };
    sessionDomain = mkOption {
      type = types.str;
      default = autheliaDefaults.sessionDomain;
    };
    port = mkOption {
      type = types.port;
      default = autheliaDefaults.port;
    };
  };

  config = mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.domain}" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
      };
    };

    services.authelia.instances.main = {
      enable = true;

      settings = {
        theme = "auto";
        default_redirection_url = "https://${cfg.domain}";

        server = {
          host = "127.0.0.1";
          port = cfg.port;
        };

        log.level = "info";

        authentication_backend.file.path = "/var/lib/authelia-main/users.yaml";

        session = {
          name = "authelia_session";
          domain = cfg.sessionDomain;
        };

        storage.local.path = "/var/lib/authelia-main/db.sqlite3";

        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

        access_control = {
          default_policy = "deny";
          rules = [];
        };

        identity_providers.oidc = {
          # Add OIDC clients here, e.g.:
          # clients = [{
          #   id = "vikunja";
          #   description = "Vikunja";
          #   secret = "$pbkdf2-sha512$..."; # hashed with: authelia crypto hash generate pbkdf2
          #   redirect_uris = [ "https://vikunja.taaltaak.org/auth/openid/authelia" ];
          #   scopes = [ "openid" "profile" "email" "groups" ];
          #   userinfo_signing_algorithm = "none";
          # }];
        };
      };

      environmentVariables = {
        AUTHELIA_JWT_SECRET_FILE = config.sops.secrets.authelia-jwt-secret.path;
        AUTHELIA_SESSION_SECRET_FILE = config.sops.secrets.authelia-session-secret.path;
        AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = config.sops.secrets.authelia-storage-key.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE = config.sops.secrets.authelia-oidc-hmac.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE = config.sops.secrets.authelia-oidc-private-key.path;
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
