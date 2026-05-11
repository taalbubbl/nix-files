{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "pgbackrest-exporter";
  version = "0.23.0";

  src = fetchFromGitHub {
    owner = "woblerr";
    repo = "pgbackrest_exporter";
    rev = "v${version}";
    # Run `nix-prefetch-url --unpack https://github.com/woblerr/pgbackrest_exporter/archive/v0.23.0.tar.gz`
    # or `nix store prefetch-file --hash-type sha256 --unpack ...` to get the real hash.
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  vendorHash = null; # repo vendors its dependencies under ./vendor

  # The repo vendors all dependencies, so we use the vendored directory.
  # buildGoModule automatically picks up ./vendor when vendorHash = null.

  ldflags = [
    "-s"
    "-w"
    "-X github.com/prometheus/common/version.Version=${version}"
    "-X github.com/prometheus/common/version.Revision=v${version}"
    "-X github.com/prometheus/common/version.Branch=master"
    "-X github.com/prometheus/common/version.BuildUser=nix"
    "-X github.com/prometheus/common/version.BuildDate=unknown"
  ];

  meta = {
    description = "Prometheus exporter for pgBackRest backup metrics";
    longDescription = ''
      pgbackrest_exporter collects metrics from pgBackRest by running
      `pgbackrest info --output json` and exposing them in Prometheus format.
      It must run on the same host as pgBackRest (or share its config/socket).
      Default listen address: :9854, metrics path: /metrics.
    '';
    homepage = "https://github.com/woblerr/pgbackrest_exporter";
    changelog = "https://github.com/woblerr/pgbackrest_exporter/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "pgbackrest_exporter";
    platforms = lib.platforms.linux;
  };
}
