{

  description = "Pythonpoets nix files";

  inputs = {
    nixpkgs.url = "github:taalbubbl/nixpkgs/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";

    # git+ssh is needed
    taalbubbl = {
      url = "git+ssh://git@github.com/taalbubbl/taalbubbl?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openpronounce = {
      url = "github:taalbubbl/OpenPronounce";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };


  outputs = { self, nixpkgs, home-manager, sops-nix, taalbubbl, openpronounce}:
  let
    overlay = final: prev: {
      pgbackrest-exporter = final.callPackage ./pkgs/pgbackrest-exporter.nix { };
      # OnlyOffice's WOPI discovery scandirs document-templates/new/en-US and
      # crashes when it doesn't exist (returns empty XML → OpenCloud nil-derefs).
      # The upstream nixpkgs package doesn't ship that dir, and has THREE subtleties
      # we have to handle in concert:
      #   (1) The package uses a custom installPhase that doesn't `runHook postInstall`,
      #       so a postInstall hook is silently dropped. Use `preFixup`/`postFixup`.
      #   (2) The bwrap sandbox doesn't read the package's /var/www directly; it uses
      #       `passthru.fhs` (a buildFHSEnv that copies documentserver/var/www at
      #       BUILD time). `overrideAttrs` on the FHS wrapper only changes the wrapper
      #       derivation hash — it doesn't re-run buildFHSEnv with new args, so the
      #       internal `fhsenv-rootfs` is unchanged. We have to call buildFHSEnv afresh.
      #   (3) The original buildFHSEnv references `onlyoffice-documentserver` from a
      #       local let-binding, not the overlaid attribute, so we pass our patched
      #       `base` explicitly when copying the var/www tree.
      # Two things upstream's buildFHSEnv for onlyoffice doesn't do by itself:
      #   (1) Copy the package's /var/www tree (documentserver assets — EJS
      #       templates, web-apps, fonts, etc.) into the FHS rootfs. Without
      #       this, the docservice can't render WOPI editor views.
      #   (2) Bind the host's /var/lib/onlyoffice/ inside the sandbox so the
      #       templates we populate at runtime (modules/opencloud.nix
      #       ExecStartPre) are visible to the docservice.
      # `overrideAttrs` on the wrapper alone doesn't re-run buildFHSEnv — must
      # construct a new one.
      onlyoffice-documentserver = let
        base = prev.onlyoffice-documentserver;
        fhsNew = prev.buildFHSEnv {
          name = "onlyoffice-wrapper";
          targetPkgs = pkgs: [
            prev.gcc-unwrapped.lib
            base
            base.passthru.fileconverter
          ];
          extraBuildCommands = ''
            # /var/lib/onlyoffice/ must exist in the rootfs so bwrap has a
            # mount point for the host bind below (otherwise bwrap tries to
            # mkdir parents in the read-only rootfs and aborts).
            mkdir -p $out/var/{lib/onlyoffice,www}
            cp -ar ${base}/var/www/* $out/var/www/
          '';
          extraBwrapArgs = [
            "--bind var/lib/onlyoffice/ var/lib/onlyoffice/"
          ];
        };
      in base.overrideAttrs (old: {
        passthru = old.passthru // { fhs = fhsNew; };
      });
    };
  in
    {
      nixosConfigurations = {
        chuchichaestli =
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              { nixpkgs.overlays = [ overlay ]; } # openpronounce.overlays.default ]; }
              taalbubbl.nixosModules.default
              openpronounce.nixosModules.default
              ./machines/chuchichaestli/default.nix
              ./modules/cloudflared.nix
              ./modules/nginx.nix
              ./modules/authelia.nix
              ./modules/opencloud.nix
              ./modules/vikunja.nix
              ./modules/analytics.nix
              ./modules/postgresql.nix
              ./modules/pgbackrest-exporter.nix

              ({ config, ... }: {
                  nix.settings = {
                    substituters = [
                      "https://nix-files.cachix.org"
                      "https://cache.nixos.org"
                      "https://cache.flox.dev"
                      "https://cuda-maintainers.cachix.org"
                    ];
                    trusted-public-keys = [
                      "nix-files.cachix.org-1:PnXUkf49ZDLHSiaQ0GPgB+FCynpa2A3SsPHRAgX+UrI="
                      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
                      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
                    ];
                  };
                  nix.extraOptions = ''
                    !include ${config.sops.secrets.github-token.path}
                  '';
                sops = {
                  defaultSopsFile = ./security/secrets.yaml;
                  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
                  secrets.vikunja-config = {
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.vikunja-client-secret = {
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.vikunja-jwt = {
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.taalbubbl = {};
                  secrets.github-token = {};
                  secrets.authelia-jwt-secret = { owner = "authelia-main"; };
                  secrets.authelia-session-secret = { owner = "authelia-main"; };
                  secrets.authelia-storage-key = { owner = "authelia-main"; };
                  secrets.authelia-oidc-hmac = { owner = "authelia-main"; };
                  secrets.authelia-oidc-private-key = { owner = "authelia-main"; };
                  secrets.opencloud-jwt-secret = { owner = "opencloud"; };
                  secrets.opencloud-collab-secret = { owner = "opencloud"; };
                  secrets.opencloud-service-account-secret = { owner = "opencloud"; };
                  Second mount of the same secret so OnlyOffice can read it as its
                  # own JWT signing key — keeps the two halves of the WOPI JWT path in
                  # sync without a second source-of-truth.
                  secrets.onlyoffice-jwt-secret = {
                     key = "opencloud-collab-secret";
                     owner = "onlyoffice";
                   };
                  # nginx needs to `include` the nonce file too — give it group read.
                  secrets.onlyoffice-security-nonce = {
                    owner = "onlyoffice";
                    group = "nginx";
                    mode = "0440";
                  };
                };
                vikunja = {
                  enable = true;
                };
                analytics = {
                  enable = true;
                  # lokiHost = "bernina";
                  # lokiPort = 3100;
                };
                authelia.enable = true;
                cloud = {
                  enable =true;
                  data_dir = "/var/lib/opencloud";
                  enable_onlyoffice = true;
                  enable_radicale = false;
                  path_radicale = "/var/lib/radicale/";
                };
              })

              # Separate module function — gives access to config
              ({ config, pkgs, ... }: {
                services.taalbubbl = {
                  enable = true;
                  database = {
                    name = "taalbubbl";
                    user = "taalbubbl";
                    host = "/run/postgresql";
                    port = 5432;
                  };
                  environmentFile = config.sops.secrets.taalbubbl.path;
                };
                 services.openpronounce = {
                   enable = true;
                   port = 8000;
                   host = "0.0.0.0";
                #   # environmentFile = "/run/secrets/openpronounce.env";
                };
                wildcloud.postgresql = {
                  enable = true;
                  postgresql = {
                    port = 5432;
                    package = pkgs.postgresql_18;
                  };
                  pgbackrest = {
                    stanzaName = "chuchichaestli";
                    repositories = [
                      {
                        s3_bucket = "pgbackups";
                        s3_region = "zurich";
                        s3_endpoint = "kaepfnach:9001";
                        s3_access_key = "GKf645bbb3f4e4dddef5f39959";
                        s3_secret_key = "c3fae00d51d40e4c9d515b0ebbe0d9fbce12c38486eb3f3a3f8873988cb9d628";
                      }
                    ];
                  };
                };
              }
              )

              sops-nix.nixosModules.sops
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.david = { ... }: {
                  programs.zsh = {
                    enable = true;
                    enableCompletion = true;
                    autosuggestion.enable = true;
                    syntaxHighlighting.enable = true;
                  };
                  home.stateVersion = "26.05";
                  home.sessionVariables = {
                    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/rbw/ssh-agent-socket";
                    EDITOR = "hx";
                  };
                };
                programs.ssh.startAgent = true;
              }
            ];
      };
    };
  };
}
