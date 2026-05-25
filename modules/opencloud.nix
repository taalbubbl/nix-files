# doc: https://github.com/NixOS/nixpkgs/pull/296679
# doc: https://mynixos.com/nixpkgs/options/services.ocis
# doc: https://github.com/NixOS/nixpkgs/blob/33b9d57c656e65a9c88c5f34e4eb00b83e2b0ca9/nixos/modules/services/web-apps/ocis.md
# TODO Filesystem has to get a bit more sophisticated. see :https://doc.owncloud.com/ocis/next/deployment/storage/general-considerations.html
#     1. NFS, low complexity somewhat scaleable: https://nixos.wiki/wiki/NFS
#     2. Alternatively, ocis supports the s3 protocol, could use cehp or seeweedfs but they are significantly more complex.
#
# https://fariszr.com/owncloud-infinite-scale-docker-setup/
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # List of ports to enable
  internal_host = "127.0.0.1";
  opencould_port = 9200;
  wopi_port = 9300;
  onlyoffice_url = "https://office.taalbubbl.org";
  opencloud_url = "https://cloud.taalbubbl.org";
  hostname = "taalbubbl.org";
  cfg = config.cloud;
in {
  options.cloud = {
    enable = mkEnableOption "Enable open cloud";
    data_dir = mkOption {
      type = types.str;
    };
    port = mkOption {
      type = types.port;
      default = opencould_port;
    };
    domain = mkOption {
      type = types.str;
      default = opencloud_url;
    };

    enable_radicale = mkOption {
      type = types.bool;
      default = false;
      description = "Radicale is a sync client for contacts, and calander";
    };
    port_radicale = mkOption {
      type = types.port;
      default = 5232;
    };
    path_radicale = mkOption {
      type = types.str;
    };

    enable_onlyoffice = mkOption {
      type = types.bool;
      default = false;
    };
    enable_full_text_search = mkOption {
      type = types.bool;
      default = false;
    };
  };
  config = mkIf cfg.enable {
    services.opencloud = {
      enable = true;
      url = cfg.domain;
      port = cfg.port;
      stateDir = cfg.data_dir;

  environment = {
    # Service wiring — no YAML config equivalent in the NixOS module
    OC_EXCLUDE_RUN_SERVICES = "idp";
    OC_ADD_RUN_SERVICES = "collaboration";
    # Running behind a reverse proxy
    PROXY_TLS = "false";
    OC_INSECURE = "true";
    # Env vars take precedence over settings file — ensure proxy uses Authelia, not itself
    OC_OIDC_ISSUER = "https://auth.${hostname}";
    PROXY_OIDC_ISSUER = "https://auth.${hostname}";
    # web.yaml's `oidc.scope` was being silently ignored; the env var is the
    # only reliable way to make the SPA request the groups scope
    WEB_OIDC_SCOPE = "openid profile email groups";
    # Secrets must be env vars (sops writes a file, not an inline value)
    OC_JWT_SECRET_FILE = config.sops.secrets.opencloud-jwt-secret.path;
    COLLABORATION_JWT_SECRET_FILE = mkIf cfg.enable_onlyoffice config.sops.secrets.opencloud-collab-secret.path;
    COLLABORATION_OO_SECRET_FILE = config.sops.secrets.opencloud-collab-secret.path;
    # Public URL where OnlyOffice (running in podman) calls back to WOPI; the
    # internal default is localhost:9300 which is unreachable from the container.
    COLLABORATION_WOPI_SRC = mkIf cfg.enable_onlyoffice "https://wopi.${hostname}";
  };

  settings = {
    log.level = "debug";

    proxy = {
      http.addr = "${internal_host}:${toString opencould_port}";
      tls = false;
      https_addr = opencloud_url;
      csp_config_file_location = "/etc/opencloud/csp.yaml";
      auto_provision_accounts = true;
      role_assignment = {
        driver = "oidc";
        oidc_role_mapper = {
          role_claim = "groups";
          # Defaults get nullified once we declare any field under `oidc_role_mapper`,
          # so list the mappings explicitly. Claim value `admin` matches what we set in
          # authelia-users.yaml.
          role_mapping = [
            { role_name = "admin";      claim_value = "admin"; }
            { role_name = "spaceadmin"; claim_value = "opencloudSpaceAdmin"; }
            { role_name = "user";       claim_value = "opencloudUser"; }
            { role_name = "user-light"; claim_value = "opencloudGuest"; }
          ];
        };
      };

      user_oidc_claim = "preferred_username";
      user_cs3_claim = "username";
      autoprovision_claim_username = "preferred_username";
      autoprovision_claim_email = "email";
      autoprovision_claim_displayname = "name";
      oidc = {
        issuer = "https://auth.${hostname}";
        rewrite_well_known = true;
        skip_user_info = false;
        access_token_verify_method = "jwt";
      };
    };

    storage_users.driver = "ocis";
    storage.metadata_driver = "ocis";

    web.web.config.oidc = {
      authority = "https://auth.${hostname}";
      metadata_url = "https://auth.${hostname}/.well-known/openid-configuration";
      client_id = "web";
      scope = "openid profile email groups";
    };

    system_user.id = "akadmin";

    collaboration = mkIf cfg.enable_onlyoffice {
      log.level = "info";
      app = {
        name = "OnlyOffice";
        product = "OnlyOffice";
        addr = onlyoffice_url;
        insecure = true;
      };
      # YAML key is `wopisrc` (one word), not `wopi.src` — used wrong key before and
       # the OnlyOffice iframe was getting WOPISrc=https://localhost:9300/... (the
       # internal collaboration bind addr leaked as default), so the editor couldn't
       # call back into WOPI from inside the podman container.
      wopi.wopisrc = "https://wopi.${hostname}";
      cs3api.datagateway.insecure = true;
    };

    frontend.app_handler.view_app_addr = mkIf cfg.enable_onlyoffice "eu.opencloud.api.collaboration";
    };
    };
    environment.etc."opencloud/csp.yaml".text = ''
      directives:
        connect-src:
          - "'self'"
          - "blob:"
          - "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
          - "https://*.${hostname}"
          ${optionalString cfg.enable_onlyoffice "- \"https://office.${hostname}\""}
        script-src:
          - "'self'"
          - "'unsafe-inline'"
          - "'unsafe-eval'"
          - "https://*.${hostname}"
        style-src:
          - "'self'"
          - "'unsafe-inline'"
        child-src: ["'self'"]
        font-src: ["'self'"]
        frame-src:
          - "'self'"
          - "blob:"
          - "https://docs.opencloud.eu"
          - "https://*.${hostname}"
          ${optionalString cfg.enable_onlyoffice "- \"https://embed.diagrams.net/\""}
        img-src:
          - "'self'"
          - "data:"
          - "blob:"
          - "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
          - "https://tile.openstreetmap.org/"
          - "https://*.${hostname}"
        media-src: ["'self'"]
        object-src: ["'self'", "blob:"]
        manifest-src: ["'self'"]
        frame-ancestors: ["'self'", "https://*.${hostname}"]
    '';
    
  services.onlyoffice = mkIf cfg.enable_onlyoffice {
    enable = true;
    hostname = "office.${hostname}";
    port = 9982;
    wopi = true;
    jwtSecretFile = config.sops.secrets.onlyoffice-jwt-secret.path;
    securityNonceFile = config.sops.secrets.onlyoffice-security-nonce.path;
  };
  # The onlyoffice module creates the virtualhost without ACME/SSL — layer them on.
  services.nginx.virtualHosts."office.${hostname}" = mkIf cfg.enable_onlyoffice {
    enableACME = true;
    forceSSL = true;
  };
  # OnlyOffice pulls in RabbitMQ which needs epmd. epmd defaults to IPv6-only and
  # this host has IPv6 disabled, so pin it to IPv4 loopback.
  services.epmd.listenStream = mkIf cfg.enable_onlyoffice "127.0.0.1";

  security.acme.acceptTerms = true;
  services.nginx = {
    virtualHosts."cloud.${hostname}" = {
      forceSSL = true;
      enableACME = true;
  
      # Everything path-related goes inside this block
      locations = {
        "/" = {
          proxyPass = "http://${internal_host}:${toString opencould_port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 24h;

            proxy_set_header Authorization $http_authorization;
            proxy_pass_header Authorization;

            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };

        "/caldav/" = mkIf cfg.enable_radicale {
          proxyPass = "http://127.0.0.1:5232/";
          extraConfig = "
            proxy_set_header X-Remote-User $remote_user; # provide username to CalDAV
            proxy_set_header X-Script-Name /caldav;
          ";
        };

        "/.well-known/caldav" = mkIf cfg.enable_radicale {
          return = "301 $scheme://$host/caldav/";
        };

        "/carddav/" = mkIf cfg.enable_radicale {
          proxyPass = "http://127.0.0.1:5232/"; # The trailing slash here is important!
          extraConfig = "
            proxy_set_header X-Remote-User $remote_user; # provide username to CalDAV
            proxy_set_header X-Script-Name /caldav;
          ";
        };
        # "/radicale/" = mkIf cfg.enable_radicale {
        #   proxyPass = "http://127.0.0.1:5232/";
        #   extraConfig = "
        #     proxy_set_header X-Remote-User $remote_user; # provide username to CalDAV
        #     proxy_set_header X-Script-Name /radicale;
        #   ";
        # };

        "/.well-known/carddav" = mkIf cfg.enable_radicale {
          return = "301 $scheme://$host/carddav/";
        };
      }; # End of locations
    };
  

  virtualHosts."wopi.${hostname}" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString wopi_port}";
    };
  };
  
  };
  
    services.radicale = mkIf cfg.enable_radicale {
      enable = true;
      settings = {
        server = {
          hosts = [ "127.0.0.1:5232" ];
          ssl = false;
        };
        auth = {
          type = "http_x_remote_user"; # disable authentication, and use the username that OpenCloud provides is
        };
        web = {
          type = "none";
        };
        storage = {
          filesystem_folder = "${cfg.path_radicale}/collections";
        };
        logging = {
          level = "debug"; # optional, enable debug logging
          bad_put_request_content = true; # only if level=debug
          request_header_on_debug = true; # only if level=debug
          request_content_on_debug = true; # only if level=debug
          response_content_on_debug = true; # only if level=debug
        };
      };
      
    };
    # 1. Create the directory automatically
      systemd.tmpfiles.rules =
        (optionals cfg.enable_radicale [
          "d ${cfg.path_radicale} 0750 radicale radicale -"
        ])
        # The NixOS onlyoffice module doesn't symlink the documentserver assets
        # into /var/www, so OnlyOffice's WOPI discovery scandir fails with ENOENT
        # and returns an empty XML doc — which crashes OpenCloud's parseWopiDiscovery.
        # The wrapper auto-binds /var into its sandbox and /nix is also bound, so a
        # symlink here is visible inside the sandbox.
        ++ (optionals cfg.enable_onlyoffice [
          "L+ /var/www/onlyoffice - - - - ${config.services.onlyoffice.package}/var/www/onlyoffice"
        ]);

      # 2. Grant the Radicale service permission to access this path
      systemd.services.radicale.serviceConfig = mkIf cfg.enable_radicale {
        ReadWritePaths = [ cfg.path_radicale ];
        # Ensure the service can create the folder if it's missing
        ConfigurationDirectory = "radicale"; 
      };

    networking.firewall.allowedTCPPorts = [9200 9980 8222 4222 9998 5232];
  };
}

