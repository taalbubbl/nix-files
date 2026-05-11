{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pgbackrest-exporter;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    escapeShellArgs
    optionals
    optionalString
    concatMap
    ;
in
{
  options.services.pgbackrest-exporter = {
    enable = mkEnableOption "pgBackRest Prometheus exporter";

    package = mkOption {
      type = types.package;
      default = pkgs.pgbackrest-exporter;
      defaultText = lib.literalExpression "pkgs.pgbackrest-exporter";
      description = "The pgbackrest_exporter package to use.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = ":9854";
      example = "127.0.0.1:9854";
      description = "Address on which to expose metrics (--web.listen-address).";
    };

    telemetryPath = mkOption {
      type = types.str;
      default = "/metrics";
      description = "HTTP path under which to expose metrics (--web.telemetry-path).";
    };

    webConfigFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a web configuration file enabling TLS or basic authentication.
        See https://github.com/prometheus/exporter-toolkit/blob/master/docs/web-configuration.md.
      '';
    };

    collectInterval = mkOption {
      type = types.int;
      default = 600;
      description = "Metrics collection interval in seconds (--collect.interval).";
    };

    backrestConfig = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/etc/pgbackrest/pgbackrest.conf";
      description = "Full path to the pgBackRest configuration file (--backrest.config).";
    };

    backrestConfigIncludePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Full path to additional pgBackRest configuration files (--backrest.config-include-path).";
    };

    stanzaInclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "main" "replica" ];
      description = "Stanzas to collect metrics for. Empty means all stanzas (--backrest.stanza-include).";
    };

    stanzaExclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "test" ];
      description = "Stanzas to exclude from metric collection (--backrest.stanza-exclude).";
    };

    backupType = mkOption {
      type = types.nullOr (types.enum [ "full" "incr" "diff" ]);
      default = null;
      description = "Restrict metric collection to a specific backup type (--backrest.backup-type).";
    };

    databaseCount = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the number of databases in backups (--backrest.database-count). Requires pgBackRest >= v2.41.";
    };

    databaseParallelProcesses = mkOption {
      type = types.int;
      default = 1;
      description = "Number of parallel processes for database count collection (--backrest.database-parallel-processes).";
    };

    databaseCountLatest = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the number of databases in the latest backups (--backrest.database-count-latest). Requires pgBackRest >= v2.41.";
    };

    referenceCount = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the number of references to other backups (--backrest.reference-count).";
    };

    verboseWal = mkOption {
      type = types.bool;
      default = false;
      description = "Expose WALMin/WALMax as additional metric labels (--backrest.verbose-wal). Creates new time series on each WAL archiving.";
    };

    collectorPgbackrest = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable the pgBackRest collector. When false, only version and build-info
        metrics are collected (--no-collector.pgbackrest).
      '';
    };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log level (--log.level).";
    };

    logFormat = mkOption {
      type = types.enum [ "logfmt" "json" ];
      default = "logfmt";
      description = "Log output format (--log.format).";
    };

    user = mkOption {
      type = types.str;
      default = "pgbackrest-exporter";
      description = "User under which the exporter runs. Must have read access to pgBackRest config/repos.";
    };

    group = mkOption {
      type = types.str;
      default = "pgbackrest-exporter";
      description = "Group under which the exporter runs.";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional flags passed verbatim to pgbackrest_exporter.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "pgBackRest exporter service user";
    };

    users.groups.${cfg.group} = { };

    systemd.services.pgbackrest-exporter = {
      description = "pgBackRest Prometheus Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart =
          let
            args =
              [
                "--web.listen-address=${cfg.listenAddress}"
                "--web.telemetry-path=${cfg.telemetryPath}"
                "--collect.interval=${toString cfg.collectInterval}"
                "--log.level=${cfg.logLevel}"
                "--log.format=${cfg.logFormat}"
                "--backrest.database-parallel-processes=${toString cfg.databaseParallelProcesses}"
              ]
              ++ optionals (cfg.webConfigFile != null) [ "--web.config.file=${cfg.webConfigFile}" ]
              ++ optionals (cfg.backrestConfig != null) [ "--backrest.config=${cfg.backrestConfig}" ]
              ++ optionals (cfg.backrestConfigIncludePath != null) [ "--backrest.config-include-path=${cfg.backrestConfigIncludePath}" ]
              ++ concatMap (s: [ "--backrest.stanza-include=${s}" ]) cfg.stanzaInclude
              ++ concatMap (s: [ "--backrest.stanza-exclude=${s}" ]) cfg.stanzaExclude
              ++ optionals (cfg.backupType != null) [ "--backrest.backup-type=${cfg.backupType}" ]
              ++ optionals cfg.databaseCount [ "--backrest.database-count" ]
              ++ optionals cfg.databaseCountLatest [ "--backrest.database-count-latest" ]
              ++ optionals cfg.referenceCount [ "--backrest.reference-count" ]
              ++ optionals cfg.verboseWal [ "--backrest.verbose-wal" ]
              ++ optionals (!cfg.collectorPgbackrest) [ "--no-collector.pgbackrest" ]
              ++ cfg.extraFlags;
          in
          "${cfg.package}/bin/pgbackrest_exporter ${escapeShellArgs args}";

        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ "/" ];
        # Allow reading pgBackRest config/repo paths if needed — loosen via
        # ReadWritePaths / ReadOnlyPaths overrides in your host config.
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallFilter = [ "@system-service" ];
        SystemCallArchitectures = "native";
      };
    };
  };
}
