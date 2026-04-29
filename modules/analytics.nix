{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let

  cfg = config.alloyJournal;

  alloyConfig = ''
    loki.source.journal "systemd" {
      path       = "/var/log/journal"
      forward_to = [loki.write.remote.receiver]
      labels = {
        host = "${cfg.hostLabel}",
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
  options.alloyJournal = {
    enable = mkEnableOption "Grafana Alloy systemd journal forwarder";

    package = mkPackageOption pkgs "grafana-alloy" { };

    hostLabel = mkOption {
      type = types.str;
      description = "Label added to all log entries to identify this host.";
      example = "my-remote-device";
    };

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

    # Alloy needs read access to the systemd journal
    users.users.alloy.extraGroups = [ "systemd-journal" ];
  };
}
