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
    # services.nginx.virtualHosts."${cfg.domain}" = {
    #   locations."/" = {
    #     proxyPass = "http://127.0.0.1:${toString cfg.port}";
    #     proxyWebsockets = true;
    #   };
    # };

    services.authelia.instances.main = {
      enable = true;
      secrets = {
        jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
        storageEncryptionKeyFile = config.sops.secrets.authelia-storage-key.path;
      };

      settings = {
        theme = "auto";
        default_redirection_url = "https://${cfg.domain}";

        server.address = "tcp://127.0.0.1:${toString cfg.port}";

        log.level = "info";

        default_2fa_method = "webauthn";

        webauthn = {
          disable = false;
          display_name = "Authelia";
          attestation_conveyance_preference = "indirect";
          selection_criteria.user_verification = "required";
          timeout = "60s";
        };

        authentication_backend.file.path = toString cfg.usersFile;

        session = {
          name = "authelia_session";
          domain = cfg.sessionDomain;
        };

        storage.local.path = "/var/lib/authelia-main/db.sqlite3";

        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

        access_control.default_policy = "two_factor";

        identity_providers.oidc.clients = [{
          client_id = "vikunja";
          client_name = "Vikunja";
          # Hash of vikunja-client-secret. Generate with:
          # authelia crypto hash generate pbkdf2 --random
          client_secret = "$pbkdf2-sha512$310000$91IwbCDI7zXRBzHeggT/Zg$L2xE6ILl5gWuZrJJl6BabxabmZtjVwt2Cz.bo4eq7qI/4E2nI8uy3p.ve34MLyD.tkSq3TdiptTWF.WOKP66Pw";
          public = false;
          authorization_policy = "two_factor";
          redirect_uris = [ "https://vikunja.taaltaak.org/auth/openid/authelia" ];
          scopes = [ "openid" "profile" "email" "groups" ];
          userinfo_signed_response_alg = "none";
        }];
      };

      environmentVariables = {
        AUTHELIA_SESSION_SECRET_FILE = config.sops.secrets.authelia-session-secret.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE = config.sops.secrets.authelia-oidc-hmac.path;
        AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE = config.sops.secrets.authelia-oidc-private-key.path;
      };
    };

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
