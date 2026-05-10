# ./modules/postgresql.Nix
# A custom Nix module for PostgreSQL that can be used to deploy a PostgreSQL server on a host with continuous backup to S3
{ config, pkgs, lib, ... }:

with lib;
let 
    cfg = config.wildcloud.postgresql;
in
{

    # Here we define the available options for the module; the public interface of the module if you will.
    # We can then define the values for these options in the configuration of our hosts to deploy the database with the desired configuration
    options.wildcloud.postgresql = {
        enable = mkEnableOption "Enable PostgreSQL";

        postgresql = {
            port = mkOption {
                type = types.port;
                default = 5432;
            };
            package = mkOption {
                type = types.package;
                default = pkgs.postgresql_18;
                description = "PostgreSQL package to use";
            };
            initialScript = mkOption {
                type = types.path;
                description = "Initial script to run on PostgreSQL server startup";
            };
        };

        pgbackrest = {
            # this particular option is a list of objects, each representing a repository for pgbackrest
            # this makes it possible to backup our database to multiple S3 buckets. We don't have to use more than one, but it's a nice feature to have
            # since we can then backup to different cloud providers and regions
        stanzaName = mkOption {                        # ← moved here, top-level
            type = types.str;
            default = "main";
            description = "Name of the pgbackrest stanza (database cluster name)";
        };

      repositories = mkOption {
        type = types.listOf (types.submodule {
          options = {
            repo_index = mkOption {
              type = types.int;
              default = 1;
            };
            s3_bucket = mkOption {
              type = types.str;
            };
            s3_backups_path = mkOption {
              type = types.str;
              default = "/backups";
            };
            s3_region = mkOption {
              type = types.str;
              default = "zuerich";
            };
            s3_endpoint = mkOption {
              type = types.str;
              default = "kaepfnach:9000";
            };
            s3_access_key = mkOption {
              type = types.str;
            };
            s3_secret_key = mkOption {
              type = types.str;
            };
          };
        });
        default = [];
        description = "S3 repositories configuration for pgbackrest backups";
      };


            # This option defines how many full backups we want to keep
            retention = {
                full = mkOption {
                    type = types.int;
                    description = "Number of full backups to keep";
                    default = 2;
                };
            };

            # And finally, this option defines the schedule for the backups
            schedule = {
                full = mkOption {
                    type = types.str;
                    description = "Schedule for full backups (systemd calendar format)";
                    default = "weekly";
                };
            };

        };
    };

    # Now that we have our options defined, here is the actual configuration that the module will apply to the host
    # It delegates most of the work to packages and modules available in Nixpkgs and NixOS, but also adds some custom logic.

    # For instance, starting a postgresql database by settings `services.postgresql.enable = true;` is a built-in feature of NixOS, but I have edited the settings
    # of the database to fit my needs.
    config = {
        
        # Start the PostgreSQL service
        services.postgresql = {
            enable = cfg.enable;

            # Use the port option we defined earlier
            port = cfg.postgresql.port;

            # Use the package option we defined earlier (which defaults to PostgreSQL 17)
            package = cfg.postgresql.package;


            ### THIS IS CONFIGURED WITH FLAKE

            # # Use the initialScript option we defined earlier, so users of this module can pass a script to run on the database server startup
            # initialScript = cfg.postgresql.initialScript;

            # # Allow all local connections and password authentication on the network
            # authentication = pkgs.lib.mkOverride 10 ''
            #     # Managed by a Nix module
            #     #type database  DBuser  auth-method
            #     local all       all     trust

            #     # allow password authentication on all interfaces
            #     host  all       all      all     scram-sha-256
            # '';

            # Configure postgres
            # This Nix option lets us declare the content of the postgresql.conf file
            # We can use it to enable WAL archiving (which is required for pgbackrest), tune performance settings, and more
            settings = {
                # Enable WAL archiving
                archive_mode = "on";
                # Here we set the command that will be used to archive the WAL files
                # We use pgbackrest to push the WAL files to the S3 bucket
                # Rather than hardcoding the path to the pgbackrest binary, we can use string interpolation to reference the pgbackrest package from Nixpkgs.
                # Nix will install this package, store it somewhere in /Nix/store, and the correct path to the binary will be reflected in the `postgresql.conf` file
                archive_command = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=${cfg.pgbackrest.stanzaName} archive-push %p";
                archive_timeout = "300";
        
                # Recommended settings for better performance
                max_wal_size = "1GB";
                min_wal_size = "80MB";
        
                # Connection settings
                listen_addresses = lib.mkForce "*";
                max_connections = "100";
            };
        };

        # Install pgbackrest
        environment.systemPackages = [ pkgs.pgbackrest ];

        # Configure pgBackRest
        # We can use environment.etc to declare the content and the ownership of a file on the host
        # We can use use the full power of the Nix language to generate the content of the file: functions, string interpolation, etc.
            environment.etc."pgbackrest/pgbackrest.conf" = {
                user = "postgres";   # ← was "owner", correct attribute is "user"
                group = "postgres";
                mode = "0640";
                text = 
            let
                # This function generates the configuration for a single repository
                # It takes a repository object as an argument and returns a string that will be used to configure the repository in the pgbackrest.conf file
                # Since we have not one but a list of repositories, we need to go through that list, apply the function to each repository, and then concatenate the results into a single string
                # that we can insert into the pgbackrest.conf file
                mkRepoConfig = repo: ''
                    repo${toString repo.repo_index}-type=s3
                    repo${toString repo.repo_index}-s3-bucket=${repo.s3_bucket}
                    repo${toString repo.repo_index}-s3-region=${repo.s3_region}
                    repo${toString repo.repo_index}-path=${repo.s3_backups_path}
                    repo${toString repo.repo_index}-s3-endpoint=${repo.s3_endpoint}
                    repo${toString repo.repo_index}-s3-key=${repo.s3_access_key}
                    repo${toString repo.repo_index}-s3-key-secret=${repo.s3_secret_key}
                    repo${toString repo.repo_index}-s3-uri-style=path
                    repo${toString repo.repo_index}-s3-verify-tls=n 
                '';
                # The concatMapStringsSep function from the Nixpkgs library does exactly what we want: it applies the function to each repository, and then concatenates the results into a single string
                # Kind of like `map + join` in javascript, or `foldMap` in haskell
                repos_config = lib.strings.concatMapStringsSep "\n" mkRepoConfig cfg.pgbackrest.repositories;
            in ''
                [global]
                ${repos_config}
                process-max=4
                log-level-console=info
                log-level-file=debug
                    
                [main]
                pg1-path=/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}
                pg1-port=${toString cfg.postgresql.port}
                
                archive-async=y
                archive-push-queue-max=4GB
                retention-full=${toString cfg.pgbackrest.retention.full}
                start-fast=y
                '';
            };
        # This is yet another example of what you can declaratively configure in NixOS: we've seen packages, files, postgresql, and now, systemd units!
        # This particular systemd service will run a full backup of the database. We can launch it manually using `systemctl start pgbackrest-full-backup`
        # or we can associate it with a systemd timer to run the backup on a schedule.
        systemd.services.pgbackrest-full-backup = {
            description = "pgBackRest Full Backup Service";
            after = [ "postgresql.service" ];
            requires = [ "postgresql.service" ];
            path = [ pkgs.pgbackrest ];
            
            serviceConfig = {
                Type = "oneshot";
                User = "postgres";
                Group = "postgres";
            };

            script = ''
                if ! pgbackrest info; then
                    pgbackrest --stanza=${cfg.pgbackrest.stanzaName} stanza-create
                fi
                pgbackrest --stanza=${cfg.pgbackrest.stanzaName} --type=full backup
            '';
        };

        # Here we define a systemd timer to run the full backup on a schedule
        systemd.timers.pgbackrest-full-backup = {
            description = "Timer for pgBackRest Full Backup";
            wantedBy = [ "timers.target" ];
            
            timerConfig = {
                # Run the backup on the schedule that was passed in the options of the module
                OnCalendar = cfg.pgbackrest.schedule.full;
                Persistent = true;
            };
        };

        # Finally, we need to create a couple of directories for pgbackrest to work
        systemd.tmpfiles.rules = [
            # Create a directory for pgbackrest logs
            "d /var/log/pgbackrest 0700 postgres postgres -"
            # Create a directory for pgbackrest transient data
            "d /var/spool/pgbackrest 0700 postgres postgres -"
        ];
    };
}
