{
  description = "Pythonpoets nix files";

  inputs = {
    nixpkgs.url = "github:taalbubbl/nixpkgs/master";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix.url = "github:ryantm/agenix";

    taalbubbl.url = "git+ssh://git@github.com/taalbubbl/taalbubbl?ref=main";
  };

  outputs = { self, nixpkgs, home-manager, agenix, taalbubbl}:
    {
      nixosConfigurations = {
        chuchichaestli =
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              taalbubbl.nixosModules.default
              ./machines/chuchichaestli/default.nix
              ./modules/cloudflared.nix
              ./modules/nginx.nix
              ./modules/vikunja.nix
              ./modules/analytics.nix
              ./modules/postgresql.nix 

              # Plain attribute set — no config references needed here
              {
                age = {
                  identityPaths = [ "/home/david/.ssh/id_ed25519" ];
                  secrets.vikunja-config = {
                    file = "/home/david/nix-files/security/vikunja-config.age";
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.vikunja-client-secret = {
                    file = "/home/david/nix-files/security/vikunja-client-secret.age";
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.vikunja-jwt = {
                    file = "/home/david/nix-files/security/vikunja-jwt.age";
                    mode = "0440";
                    group = "keys";
                  };
                  secrets.taalbubbl = {
                    file = "/home/david/nix-files/security/taalbubbl.age";
                  };
                };
                vikunja = {
                  enable = true;
                };
                analytics = {
                  enable = true;
                  lokiHost = "bernina";
                  lokiPort = 3100;
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
                  environmentFile = config.age.secrets.taalbubbl.path;
                };
                wildcloud.postgresql = {
                  enable = true;
                  postgresql = {
                    port = 5432;
                    package = pkgs.postgresql_18;                    
                  };
                  pgbackrest = {
                    repositories = [
                      {
                        stanzaName = "chuchichaestli";
                        s3_bucket = "pgbackups"; 
                        s3_region = "zuerich"; 
                        s3_endpoint = "http://kaepfnach:9000";
                        s3_access_key = "GKf645bbb3f4e4dddef5f39959";
                        s3_secret_key = "c3fae00d51d40e4c9d515b0ebbe0d9fbce12c38486eb3f3a3f8873988cb9d628";
                      }
                    ];
                  };
                };
              }
              )

              agenix.nixosModules.default
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
