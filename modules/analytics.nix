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
      ];
    };

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = ["systemd"];
      port = 9002;
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
