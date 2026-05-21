{
    services.cloudflared = {
      enable = true;
      tunnels = {
      "8e979e98-e5fe-4d52-9112-ad4b2f10b955" = {
        credentialsFile = "/home/david/.cloudflared/8e979e98-e5fe-4d52-9112-ad4b2f10b955.json";
        default = "http_status:404";
        ingress = {
          "taalbubbl.org" = "http://127.0.0.1:80";
          "*.taalbubbl.org" = "http://127.0.0.1:80";
        };
      };
      };
    };
}