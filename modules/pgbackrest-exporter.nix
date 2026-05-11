{ config, lib, pkgs, options, ... }:

let
  cfg = config.services.prometheus.exporters.pgbackrest;
  inherit (lib)
    mkOption
    types
    concatMap
    optionals
    escapeShellArgs
    ;
in
{
  options.services.prometheus.exporters.pgbackrest = {
    enable = lib.mkEnableOption "pgBackRest Prometheus exporter";

    package = mkOption {
      type = types.package;
      default = pkgs.pgbackrest-exporter;
      defaultText = lib.literalExpression "pkgs.pgbackrest-exporter";
      description = "The pgbackrest_exporter package to use.";
    };

    pgbackrestPackage = mkOption {
      type = types.package;
      default = pkgs.pgbackrest;
      defaultText = lib.literalExpression "pkgs.pgbackrest";
      description = "The pgBackRest package to put on PATH for the exporter.";
    };

    port = mkOption {
      type = types.port;
      default = 9854;
      description = "Port on which to expose metrics.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address on which to expose metrics.";
    };

    telemetryPath = mkOption {
      type = types.str;
      default = "/metrics";
      description = "HTTP path under which to expose metrics.";
    };

    webConfigFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to web config file for TLS/basic-auth (exporter-toolkit format).";
    };

    collectInterval = mkOption {
      type = types.int;
      default = 600;
      description = "Metrics collection interval in seconds.";
    };

    backrestConfig = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/etc/pgbackrest/pgbackrest.conf";
      description = "Full path to the pgBackRest configuration file.";
    };

    backrestConfigIncludePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Full path to additional pgBackRest configuration files.";
    };

    stanzaInclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "main" ];
      description = "Stanzas to collect metrics for. Empty = all stanzas.";
    };

    stanzaExclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Stanzas to exclude from metric collection.";
    };

    backupType = mkOption {
      type = types.nullOr (types.enum [ "full" "incr" "diff" ]);
      default = null;
      description = "Restrict collection to a specific backup type.";
    };

    databaseCount = mkOption {
      type = types.bool;
      default = false;
      description = "Expose number of databases in backups. Requires pgBackRest >= v2.41.";
    };

    databaseParallelProcesses = mkOption {
      type = types.int;
      default = 1;
      description = "Parallel processes for database count collection.";
    };

    databaseCountLatest = mkOption {
      type = types.bool;
      default = false;
      description = "Expose number of databases in latest backups. Requires pgBackRest >= v2.41.";
    };

    referenceCount = mkOption {
      type = types.bool;
      default = false;
      description = "Expose number of references to other backups.";
    };

    verboseWal = mkOption {
      type = types.bool;
      default = false;
      description = "Expose WALMin/WALMax as additional metric labels.";
    };

    collectorPgbackrest = mkOption {
      type = types.bool;
      default = true;
      description = "Enable pgBackRest collector. When false, only version/build-info metrics are collected.";
    };

    logLevel = mkOption {
      type = types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log level.";
    };

    logFormat = mkOption {
      type = types.enum [ "logfmt" "json" ];
      default = "logfmt";
      description = "Log output format.";
    };

    user = mkOption {
      type = types.str;
      default = "postgres";
      description = "User to run the exporter as. Needs read access to pgBackRest config/repos.";
    };

    group = mkOption {
      type = types.str;
      default = "postgres";
      description = "Group to run the exporter as.";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional flags passed verbatim to pgbackrest_exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services."prometheus-pgbackrest-exporter" = {
      description = "pgBackRest Prometheus Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # Make pgbackrest binary available in the service's PATH
      path = [ cfg.pgbackrestPackage ];

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;

        ExecStart =
          let
            args =
              [
                "--web.listen-address=${cfg.listenAddress}:${toString cfg.port}"
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

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
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
