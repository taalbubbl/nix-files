{
  description = "Pythonpoets nix files";

  inputs = {
    nixpkgs.url = "github:taalbubbl/nixpkgs/master";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";

    taalbubbl.url = "git+ssh://git@github.com/taalbubbl/taalbubbl?ref=main";
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, taalbubbl}:
  let
    overlay = final: prev: {
      pgbackrest-exporter = final.callPackage ./pkgs/pgbackrest-exporter.nix { };
    };
  in
    {
      nixosConfigurations = {
        chuchichaestli =
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              { nixpkgs.overlays = [ overlay ]; }
              taalbubbl.nixosModules.default
              ./machines/chuchichaestli/default.nix
              ./modules/cloudflared.nix
              ./modules/nginx.nix
              ./modules/authelia.nix
              ./modules/opencloud.nix
              ./modules/vikunja.nix
              ./modules/analytics.nix
              ./modules/postgresql.nix
              ./modules/pgbackrest-exporter.nix

              # Plain attribute set — no config references needed here
              {
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
                  secrets.authelia-jwt-secret = { owner = "authelia-main"; };
                  secrets.authelia-session-secret = { owner = "authelia-main"; };
                  secrets.authelia-storage-key = { owner = "authelia-main"; };
                  secrets.authelia-oidc-hmac = { owner = "authelia-main"; };
                  secrets.authelia-oidc-private-key = { owner = "authelia-main"; };
                  secrets.opencloud-jwt-secret = { owner = "opencloud"; };
                  secrets.opencloud-collab-secret = { owner = "opencloud"; };
                  # Second mount of the same secret so OnlyOffice can read it as its
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
                  path_radicale = "//var/lib/radicale/";
                  #config_file = "/data1/ocis/config/";
                };
              }

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
