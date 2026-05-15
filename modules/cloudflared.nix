{
    services.cloudflared = {
      enable = true;
      tunnels = {
      "8e979e98-e5fe-4d52-9112-ad4b2f10b955" = {
        credentialsFile = "/home/david/.cloudflared/8e979e98-e5fe-4d52-9112-ad4b2f10b955.json";
        default = "http_status:404";
        ingress = {
          "taaltaak.org" = "http://localhost:80";
          "*.taaltaak.org" = "http://127.0.0.1:80";
          "auth.taalbubbl.org" = "http://127.0.0.1:80";
        };
      };
      };
    };
}