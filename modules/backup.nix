# pgBackRest — production PostgreSQL backup with PITR
# https://pgbackrest.org/user-guide.html
#
# Architecture:
#   DB host (this machine)  --SSH-->  Repo host (kaepfnach)
#
# Setup steps before deploying:
#   1. Install pgbackrest on kaepfnach (same version as this host)
#   2. Create a 'pgbackrest' user on kaepfnach
#   3. mkdir -p /data1/pgbackrest && chown pgbackrest: /data1/pgbackrest
#   4. Exchange SSH keys:
#        sudo -u postgres ssh-keygen -t ed25519 -N "" -f ~postgres/.ssh/id_ed25519
#        # copy postgres@dbhost pubkey → pgbackrest@kaepfnach ~/.ssh/authorized_keys
#        # copy pgbackrest@kaepfnach pubkey → postgres@dbhost ~/.ssh/authorized_keys
#   5. After nixos-rebuild switch:
#        sudo -u pgbackrest pgbackrest --stanza=myapp stanza-create
#        sudo -u pgbackrest pgbackrest --stanza=myapp check
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  stanzaName = "taalbubbl";
  repoHost   = "kaepfnach";
  repoUser   = "pgbackrest";
  repoPath   = "/data1/pgbackrest";
  pgDataDir  = config.services.postgresql.dataDir;
  pgUser     = "postgres";
in {
  # ============================================================
  # 1. pgBackRest config
  # ============================================================
  environment.systemPackages = [ pkgs.pgbackrest ];

  systemd.tmpfiles.rules = [
    "d /etc/pgbackrest     0750 ${pgUser} ${pgUser} -"
    "d /var/log/pgbackrest 0750 ${pgUser} ${pgUser} -"
  ];

  environment.etc."pgbackrest/pgbackrest.conf".text = ''
    [global]
    repo1-host=${repoHost}
    repo1-host-user=${repoUser}
    repo1-host-type=ssh
    repo1-path=${repoPath}
    repo1-retention-full=2
    repo1-retention-diff=7

    log-level-console=info
    log-level-file=detail
    log-path=/var/log/pgbackrest

    process-max=2
    start-fast=y

    [${stanzaName}]
    pg1-path=${pgDataDir}
    pg1-user=${pgUser}
  '';

  # ============================================================
  # 2. PostgreSQL — enable WAL archiving
  # ============================================================
  services.postgresql.settings = {
    archive_mode    = "on";
    archive_command = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=${stanzaName} archive-push %p";
    archive_timeout = 60; # max 60s data loss window when idle
    max_wal_senders = 3;
    wal_level       = "replica";
  };

  systemd.services.postgresql.serviceConfig.ReadWritePaths = [
    "/var/log/pgbackrest"
  ];

  # ============================================================
  # 3. Backup services
  # ============================================================

  # Full backup — weekly (Sunday)
  systemd.services.pgbackrest-full = {
    description = "pgBackRest full backup (${stanzaName})";
    serviceConfig = {
      Type = "oneshot";
      User = pgUser;
    };
    script = ''
      ${pkgs.pgbackrest}/bin/pgbackrest \
        --stanza=${stanzaName} \
        --type=full \
        backup
    '';
  };
  systemd.timers.pgbackrest-full = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 01:00";
      Persistent = true;
    };
  };

  # Differential backup — daily Mon-Sat
  systemd.services.pgbackrest-diff = {
    description = "pgBackRest differential backup (${stanzaName})";
    serviceConfig = {
      Type = "oneshot";
      User = pgUser;
    };
    script = ''
      ${pkgs.pgbackrest}/bin/pgbackrest \
        --stanza=${stanzaName} \
        --type=diff \
        backup
    '';
  };
  systemd.timers.pgbackrest-diff = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Sat 01:00";
      Persistent = true;
    };
  };
}
