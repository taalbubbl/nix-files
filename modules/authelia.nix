{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  autheliaDefaults = {
    domain = "auth.taalbubbl.org";
    sessionDomain = "taalbubbl.org";
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
    usersFile = mkOption {
      type = types.path;
      default = ../security/authelia-users.yaml;
      description = "Path to the Authelia users database file.";
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
      secrets = {
        jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
        storageEncryptionKeyFile = config.sops.secrets.authelia-storage-key.path;
      };

      settings = {
        theme = "auto";

        server.address = "tcp://127.0.0.1:${toString cfg.port}";

        log.level = "info";

        authentication_backend.file.path = toString cfg.usersFile;

        session = {
          name = "authelia_session";
          cookies = [{
            domain = cfg.sessionDomain;
            authelia_url = "https://${cfg.domain}";
          }];
        };

        storage.local.path = "/var/lib/authelia-main/db.sqlite3";

        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

        access_control.default_policy = "one_factor";

        identity_providers.oidc.clients = [
          {
          client_id = "vikunja";
          client_name = "Vikunja";
          # Hash of vikunja-client-secret. Generate with:
          # authelia crypto hash generate pbkdf2 --random
          client_secret = "$pbkdf2-sha512$310000$83cZJwDGDOadBAQfbHzJ8g$ljMg2q44.FCZohmGYi/kSBuvE8wkL91GlG8enw9o174Pjhp1A3kmeBZ0VxxjBwlkCXzmjlrR4kcF6IoIqgP8Yg";
          public = false;
          authorization_policy = "one_factor";
          require_pkce = false;
          token_endpoint_auth_method = "client_secret_basic";
          redirect_uris = [ "https://vikunja.taalbubbl.org/auth/openid/authelia" ];
          scopes = [ "openid" "profile" "email" ];
          response_types = [ "code" ];
          grant_types = [ "authorization_code" ];
          userinfo_signed_response_alg = "none";
        }
        {
          client_id = "web";
          client_name = "OpenCloud";
          public = true;
          authorization_policy = "one_factor";
          require_pkce = true;
          token_endpoint_auth_method = "none";
          redirect_uris = [
            "https://cloud.taalbubbl.org/oidc-callback.html"
            "https://cloud.taalbubbl.org/oidc-silent-redirect.html"
          ];
          scopes = [ "openid" "profile" "email" ];
          response_types = [ "code" ];
          grant_types = [ "authorization_code" "refresh_token" ];
          userinfo_signed_response_alg = "none";
        }
        ];
      };

      environmentVariables = {
        AUTHELIA_SESSION_SECRET_FILE = config.sops.secrets.authelia-session-secret.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE = config.sops.secrets.authelia-oidc-hmac.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE = config.sops.secrets.authelia-oidc-private-key.path;
      };
    };

    # Port only accessible via nginx — not opened in firewall directly.
  };
}
