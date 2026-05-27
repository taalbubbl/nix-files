{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "8e979e98-e5fe-4d52-9112-ad4b2f10b955" = {
        credentialsFile = "/home/david/.cloudflared/8e979e98-e5fe-4d52-9112-ad4b2f10b955.json";
        default = "http_status:404";
        ingress = {
          "taalbubbl.org" = {
            service = "https://127.0.0.1:443";
            originRequest = {
              originServerName = "taalbubbl.org";
              noTLSVerify = true;
            };
          };
          "*.taalbubbl.org" = {
            service = "https://127.0.0.1:443";
            originRequest = {
              # SNI will be the requested hostname automatically when noTLSVerify
              # is true and no originServerName is set on a wildcard. nginx then
              # picks the vhost via the Host header, which cloudflared forwards.
              noTLSVerify = true;
            };
          };
        };
      };
    };
  };
}