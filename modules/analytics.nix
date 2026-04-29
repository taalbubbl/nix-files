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
        host = "${cfg.lokiHost}",
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
        url = "http://${cfg.lokiHost}:${toString cfg.lokiPort}/loki/api/v1/push"
      }
    }
  '';

in {
  options.analytics = {
    enable = mkEnableOption "Grafana Alloy systemd journal forwarder";

    package = mkPackageOption pkgs "grafana-alloy" { };


    lokiHost = mkOption {
      type = types.str;
      description = "IP address or hostname of the Loki instance to push logs to.";
      example = "192.168.1.10";
    };

    lokiPort = mkOption {
      type = types.port;
      default = 3100;
      description = "Port of the Loki HTTP API.";
    };
  };

  config = mkIf cfg.enable {

    environment.etc."alloy/config.alloy".text = alloyConfig;

    services.alloy = {
      enable = true;
      package = cfg.package;
      configPath = "/etc/alloy/config.alloy";
    };

    # Grant journal access at the systemd unit level — do NOT touch users.users.alloy
    # as services.alloy already manages that user internally
    systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
  };
}
