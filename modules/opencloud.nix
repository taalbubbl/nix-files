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

  # draw.io is a pure frontend web extension (no backend / WOPI). It ships as a
  # release zip from opencloud-eu/web-extensions; the editor itself runs in an
  # iframe served from https://embed.diagrams.net (see CSP frame-src below).
  drawioZip = pkgs.fetchurl {
    url = "https://github.com/opencloud-eu/web-extensions/releases/download/draw-io-v2.0.0/draw-io-2.0.0.zip";
    hash = "sha256-WvWdYK0kT2Cb9/zAitB9IhA+uUrzY/Gj9H15Q/WPP80=";
  };
  # OpenCloud's web service loads custom apps from WEB_ASSET_APPS_PATH (additive
  # to the built-in apps). The zip already contains a top-level `draw-io/` folder
  # with manifest.json, so unzipping it here yields `${opencloudWebApps}/draw-io`.
  opencloudWebApps = pkgs.runCommand "opencloud-web-apps" {
    nativeBuildInputs = [ pkgs.unzip ];
  } ''
    mkdir -p $out
    unzip ${drawioZip} -d $out
  '';
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
    enable_drawio = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the draw.io web app extension (diagram editor) in OpenCloud Web.";
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
        # Load custom web apps (draw.io) from a read-only store path. Additive to
        # the built-in apps; the web service auto-discovers anything here.
        WEB_ASSET_APPS_PATH = mkIf cfg.enable_drawio "${opencloudWebApps}";
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
        # Internal service-to-service auth (sharing, graph, ocs, frontend → users service).
        # Distinct from OIDC: Authelia auths end users; this auths microservices to each other.
        # OC_SERVICE_ACCOUNT_SECRET is sourced via EnvironmentFile (sops template) below —
        # OpenCloud's sharing service doesn't honor the `_FILE` suffix for this var.
        OC_SERVICE_ACCOUNT_ID = "df05a249-75f4-4d12-8399-aa9d793e3899";
        COLLABORATION_JWT_SECRET_FILE = mkIf cfg.enable_onlyoffice config.sops.secrets.opencloud-collab-secret.path;
        COLLABORATION_OO_SECRET_FILE = config.sops.secrets.opencloud-collab-secret.path;
        # Public URL where OnlyOffice (running in podman) calls back to WOPI; the
        # internal default is localhost:9300 which is unreachable from the container.
        COLLABORATION_WOPI_SRC = mkIf cfg.enable_onlyoffice "https://wopi.${hostname}";
        # Force the service bind behavior exactly as specified in the docs
        COLLABORATION_HTTP_ADDR = "127.0.0.1:${toString wopi_port}";
        # Tell the proxy container framework to route the internal WOPI endpoint mapping
        PROXY_ENABLE_WOPI = "true";
        # OnlyOffice's nixpkgs package doesn't generate the RSA proof keys (publicKey/
        # modulus/exponent stay empty in config), so its WOPI discovery has no
        # <proof-key> element and OpenCloud rejects every callback. Disable proof-key
        # verification — JWT (COLLABORATION_OO_SECRET) still authenticates the channel.
        COLLABORATION_APP_PROOF_DISABLE = mkIf cfg.enable_onlyoffice "true";

        # Force the collaboration framework to recognize OpenCloud as the parent origin domain
        COLLABORATION_APP_PARENT_ORIGIN = "https://cloud.${hostname}";
        PROXY_ALLOWED_ORIGINS = "https://cloud.${hostname},https://office.${hostname},https://wopi.${hostname}";
        # Force opencloud frontend handler to forward documents explicitly to the collaboration microservice
  FRONTEND_SECURE_VIEW_APP_ADDR = "eu.opencloud.api.collaboration";
  
  # Tell the server engine exactly which app matches the registration context
  COLLABORATION_APP_NAME = "OnlyOffice";
  COLLABORATION_APP_PRODUCT = "OnlyOffice";
      };

      settings = {
        log.level = "debug";

        proxy = {
          http.addr = "${internal_host}:${toString opencould_port}";
          tls = false;
          https_addr = opencloud_url;
          csp_config_file_location = "/etc/opencloud/csp.yaml";
          auto_provision_accounts = true;
          # Map the web endpoint routing boundary
          wopi_url = "https://wopi.${hostname}";
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

        frontend.app_handler = {
          view_app_addr = "eu.opencloud.api.collaboration";
          secure_view_app_addr = "eu.opencloud.api.collaboration";
        };
      };
    };

    # Render the service-account secret into a KEY=value env file and feed it to
    # the opencloud unit as EnvironmentFile. `_FILE` suffix isn't honored by the
    # sharing service for OC_SERVICE_ACCOUNT_SECRET, so we inline the value.
    sops.templates."opencloud-service-account.env" = {
      content = ''
        OC_SERVICE_ACCOUNT_SECRET=${config.sops.placeholder.opencloud-service-account-secret}
      '';
      owner = "opencloud";
    };

    systemd.services.opencloud.serviceConfig.EnvironmentFile = [
      config.sops.templates."opencloud-service-account.env".path
    ];

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
          ${optionalString cfg.enable_drawio "- \"https://embed.diagrams.net/\""}
          ${optionalString cfg.enable_onlyoffice "- \"https://office.${hostname}\""}
          ${optionalString cfg.enable_onlyoffice "- \"https://wopi.${hostname}\""}
         
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
      loglevel = "info";
      enable = true;
      hostname = "office.${hostname}";
      port = 9982;
      wopi = true;
      # OpenCloud's WOPI callback ultimately hits 127.0.0.1 via the nginx
      # reverse proxy. OnlyOffice's request-filtering-agent blocks
      # private/loopback addresses by default; opt back in. (Replaces the
      # `allowPrivateIPAddress = true` patch we used to carry in the nixpkgs
      # fork — upstream now exposes it as this option.)
      allowLocalConnections = true;
      jwtSecretFile = config.sops.secrets.onlyoffice-jwt-secret.path;
      securityNonceFile = config.sops.secrets.onlyoffice-security-nonce.path;
    };

    # The onlyoffice module automatically creates the virtualhost.
    # The OpenCloud SPA prepends a cache-busting "<version>-<nixhash>/" prefix
    # to every OnlyOffice asset URL (e.g. /9.3.1-cyafpzzj.../web-apps/...).
    # The docservice itself serves these paths at the ROOT (/web-apps/...),
    # NOT under a version directory, so we strip the entire prefix.
    services.nginx.virtualHosts."office.${hostname}" = mkIf cfg.enable_onlyoffice {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        rewrite ^/[0-9]+\.[0-9]+\.[0-9]+-[^/]+/(web-apps|sdkjs|sdkjs-plugins|fonts|dictionaries|welcome)(/.*)$ /$1$2 last;
        rewrite ^/[0-9]+\.[0-9]+\.[0-9]+-[^/]+/(doc|downloadas)(/.*)$ /$1$2 last;

        # REMOVED X-Frame-Options ALLOW-FROM entirely. Use only standard CSP:
        add_header Content-Security-Policy "frame-ancestors 'self' https://cloud.${hostname} https://wopi.${hostname}" always;
      '';

      locations."~ ^/(web-apps|sdkjs|sdkjs-plugins|fonts|dictionaries)" = {
        extraConfig = ''
          add_header Access-Control-Allow-Origin "https://cloud.${hostname}" always;
          add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
          add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;

          # Align location-level framing to match
          add_header Content-Security-Policy "frame-ancestors 'self' https://cloud.${hostname} https://wopi.${hostname}" always;
        '';
      };
    };

    # OnlyOffice pulls in RabbitMQ which needs epmd. epmd defaults to IPv6-only and
    # this host has IPv6 disabled, so pin it to IPv4 loopback.
    services.epmd.listenStream = mkIf cfg.enable_onlyoffice "127.0.0.1";

    # OnlyOffice's WOPI discovery reads `services.CoAuthoring.server.newFileTemplate`
    # and scandirs `<that>/<TEMPLATES_DEFAULT_LOCALE>/` (en-US) to decide which
    # file extensions to advertise. Upstream default is a cwd-relative path
    # ("../../document-templates/new"); inside the bwrap sandbox cwd is "/", so
    # it resolves to /document-templates/new — doesn't exist, readdir fails, the
    # in-process cache becomes {}, /hosting/discovery emits <app> entries with
    # zero <action> children, and OpenCloud registers no file handlers.
    #
    # Fix: create the templates on the host under /var/lib/onlyoffice/... (which
    # is bind-mounted into the sandbox, so the files become visible at the same
    # path inside), then rewrite the config to an absolute path pointing there.
    # NODE_ENV=production-linux makes node-config merge production-linux.json on
    # top of default.json, so we must patch BOTH or the production override
    # clobbers our fix.
    systemd.services.onlyoffice-docservice.serviceConfig.ExecStartPre =
      mkIf cfg.enable_onlyoffice (lib.mkAfter [
        (pkgs.writeShellScript "onlyoffice-fix-templates" ''
          set -eu
          tmpl=/var/lib/onlyoffice/documentserver/document-templates/new/en-US
          mkdir -p "$tmpl"
          for ext in docx docxf xlsx pptx pdf odt ods odp rtf txt csv html epub fb2; do
            : > "$tmpl/new.$ext"
          done
          for f in /run/onlyoffice/config/default.json /run/onlyoffice/config/production-linux.json; do
            ${pkgs.jq}/bin/jq \
              '.services.CoAuthoring.server.newFileTemplate = "/var/lib/onlyoffice/documentserver/document-templates/new"' \
              "$f" | ${pkgs.moreutils}/bin/sponge "$f"
          done
          # The wopi.{word,cell,slide,pdf}{View,Edit} arrays drive which file
          # extensions get emitted as <action ext="..."> in /hosting/discovery.
          # Upstream defaults are empty arrays — that's why apps came out with
          # zero actions and OpenCloud's collaboration service registered no
          # handlers.
          #
          # Restricted to formats OnlyOffice handles natively (no x2t
          # conversion). ODF (odt/ods/odp) and legacy MS (doc/xls/ppt) need
          # x2t which fails with ExitCode 80 in our packaging — re-add them
          # only once x2t is verified working for those formats.
          ${pkgs.jq}/bin/jq '
              .wopi.wordView  = ["docx","docxf","oform"]
            | .wopi.wordEdit  = ["docx","docxf","oform"]
            | .wopi.cellView  = ["xlsx"]
            | .wopi.cellEdit  = ["xlsx"]
            | .wopi.slideView = ["pptx"]
            | .wopi.slideEdit = ["pptx"]
            | .wopi.pdfView   = ["pdf"]
            | .wopi.pdfEdit   = ["pdf"]
          ' /run/onlyoffice/config/default.json \
            | ${pkgs.moreutils}/bin/sponge /run/onlyoffice/config/default.json
        '')
      ]);

    security.acme.acceptTerms = true;

    services.nginx.virtualHosts."cloud.${hostname}" = {
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
            extraConfig = ''
              proxy_set_header X-Remote-User $remote_user; # provide username to CalDAV
              proxy_set_header X-Script-Name /caldav;
            '';
          };

          "/.well-known/caldav" = mkIf cfg.enable_radicale {
            return = "301 $scheme://$host/caldav/";
          };

          "/carddav/" = mkIf cfg.enable_radicale {
            proxyPass = "http://127.0.0.1:5232/"; # The trailing slash here is important!
            extraConfig = ''
              proxy_set_header X-Remote-User $remote_user; # provide username to CalDAV
              proxy_set_header X-Script-Name /caldav;
            '';
          };

          "/.well-known/carddav" = mkIf cfg.enable_radicale {
            return = "301 $scheme://$host/carddav/";
          };
        }; # End of locations
    };

    services.nginx.virtualHosts."wopi.${hostname}" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString wopi_port}";
        extraConfig = ''
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
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
          type = "http_x_remote_user"; # disable authentication, and use the username that OpenCloud provides
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
    systemd.tmpfiles.rules = mkIf cfg.enable_radicale [
      "d ${cfg.path_radicale} 0750 radicale radicale -"
    ];

    # 2. Grant the Radicale service permission to access this path
    systemd.services.radicale.serviceConfig = mkIf cfg.enable_radicale {
      ReadWritePaths = [ cfg.path_radicale ];
      # Ensure the service can create the folder if it's missing
      ConfigurationDirectory = "radicale";
    };

    networking.firewall.allowedTCPPorts = [9200 9980 8222 4222 9998 5232];
  };
}
