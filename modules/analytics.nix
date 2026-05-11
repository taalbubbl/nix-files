{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.analytics;

  alloyConfig = ''
    loki.source.journal "systemd" {
      path       = "/var/log/journal"
      forward_to = [loki.write.remote.receiver]
      max_age    = "720h"
      labels = {
        host = constants.hostname,
        job  = "systemd-journal",
      }
      relabel_rules = loki.relabel.journal.rules
    }

    loki.relabel "journal" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
    }

    loki.write "remote" {
      endpoint {
        url = "http://127.0.0.1:${toString cfg.portLoki}/loki/api/v1/push"
      }
    }
  '';
in {
  options.analytics = {
    enable = mkEnableOption "Enable Analytics service";

    domain = mkOption {
      type = types.str;
      default = "grafana.taalbubbl.org";
    };
    port = mkOption {
      type = types.port;
      default = 2342;
    };
    portLoki = mkOption {
      type = types.port;
      default = 3100;
    };
    portPrometheus = mkOption {
      type = types.port;
      default = 3014;
    };
    alloyPackage = mkPackageOption pkgs "grafana-alloy" { };
  };

  config = mkIf cfg.enable {

    # ── Grafana ───────────────────────────────────────────────────────────────
    services.grafana = {
      enable = true;
      settings = {
        auth.disable_login_form = false;
        security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.port;
          enable_gzip = true;
          domain = cfg.domain;
          allow_embedding = true;
        };
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString cfg.portPrometheus}";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:${toString cfg.portLoki}";
          }
        ];
      };
    };

    # ── Prometheus ────────────────────────────────────────────────────────────
    services.prometheus = {
      enable = true;
      port = cfg.portPrometheus;
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
            }
          ];
        }
        {
          job_name = "pgbackrest";
          static_configs = [{
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.pgbackrest.port}"];
          }];
        }
        {
          job_name = "postgres";
          static_configs = [{
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.postgres.port}"];
          }];
        }
      ];
    };
    # ── pgBackRest Exporter ───────────────────────────────────────────────────
    services.prometheus.exporters.pgbackrest = {
      enable = true;
      # The exporter needs to run as a user that can read pgbackrest configs/logs
      # Often this is 'postgres' or 'pgbackrest'
      user = "postgres"; 
      port = 9854;
    };

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = ["systemd"];
      port = 9002;
    };

    services.prometheus.exporters.postgres = {
      enable = true;
      # The connection string. If your DB is local and allows peer auth:
      # "postgresql:///postgres?host=/run/postgresql&sslmode=disable"
      # Otherwise use: "postgresql://username:password@localhost:5432/postgres?sslmode=disable"
      dataSourceName = "postgresql:///postgres?host=/run/postgresql&sslmode=disable";
      port = 9187;
    };

    # ── Loki ──────────────────────────────────────────────────────────────────
    services.loki = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = cfg.portLoki;
          http_listen_address = "127.0.0.1";
        };

        auth_enabled = false;

        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };

        limits_config = {
          reject_old_samples = false;
          reject_old_samples_max_age = "8760h"; # 1 year
          max_global_streams_per_user = 10000;
          ingestion_rate_mb = 64;
          ingestion_burst_size_mb = 128;
        };

        schema_config.configs = [
          {
            from = "2020-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];

        query_range.results_cache.cache.embedded_cache = {
          enabled = true;
          max_size_mb = 100;
        };
      };
    };

    # ── Alloy ─────────────────────────────────────────────────────────────────
    environment.etc."alloy/config.alloy".text = alloyConfig;

    services.alloy = {
      enable = true;
      package = cfg.alloyPackage;
      configPath = "/etc/alloy/config.alloy";
    };

    systemd.services.alloy.serviceConfig.SupplementaryGroups = ["systemd-journal"];
  };
}
