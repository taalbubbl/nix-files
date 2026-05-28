
{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/david/nix-files"; # sets NH_OS_FLAKE variable for you
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];


  networking.hostName = "chuchichaestli"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  # Issue with ms edge tts feature. 
  # It wanted to connect to ipv6 but there was a dns issue
  # switching to ipv4 solves the issue
  networking.enableIPv6 = false;

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.enp2s0.disable_ipv6" = 1;
  };

  security.sudo.extraRules = [
  {
    users = [ "david" "tonda" ];
    commands = [
      { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-env";       options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl";     options = [ "NOPASSWD" ]; }
      { command = "/nix/store/*";                             options = [ "NOPASSWD" ]; }
    ];
  }
];


  # Set your time zone.
  time.timeZone = "Europe/Zurich";
  programs.zsh.enable = true;
  users.users.david = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "david";
    extraGroups = [ "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = 
    let
      keysContent = builtins.readFile (builtins.fetchurl {
        url = "https://github.com/pythonpoet.keys";
        sha256 = "sha256:01mfvwr9ar70mqygly653qdia67i4jg7kqvfannl7pqxf6qp5s9x";
      });
    in
    builtins.filter (key: key != "") 
      (lib.strings.splitString "\n" keysContent);
  };
  users.users.tonda = {
    isNormalUser = true;
    description = "Tonda";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = 
    let
      keysContent = builtins.readFile (builtins.fetchurl {
        url = "https://github.com/styn10.keys";
        sha256 = "sha256:1xnp103in2m7pxp821mvs39w91142bixdzyczr6plnincgr107hc";
      });
    in
    builtins.filter (key: key != "") 
      (lib.strings.splitString "\n" keysContent);
  };
  users.users.markus = {
    isNormalUser = true;
    description = "Markus";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = 
    let
      keysContent = builtins.readFile (builtins.fetchurl {
        url = "https://github.com/markus772.keys";
        sha256 = "sha256:1s0q5ir3dvgix2wy8l4qpdfr5fjadc028yrycj11aqmw8mmfxh48";
      });
    in
    builtins.filter (key: key != "") 
      (lib.strings.splitString "\n" keysContent);
  };
  users.users.mika = {
    isNormalUser = true;
    description = "Mika";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = 
    let
      keysContent = builtins.readFile (builtins.fetchurl {
        url = "https://github.com/sjiub.keys";
        sha256 = "sha256:17sd3qx59ngly4pdx2w09hkak9xj25wl9xdwdqisbza8frfvzvir";
      });
    in
    builtins.filter (key: key != "") 
      (lib.strings.splitString "\n" keysContent);
  };
  # Add users to taaltaak group
  users.groups.taalbubbl = {
    members = [ "david" "tonda" "markus" "mika"];
  };

  systemd.tmpfiles.rules = [
    "Z /opt/taalbubbl 0770 taalbubbl taalbubbl -"
  ];
  
   
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
   git
   helix
   wget
   curl
   tmux
   cloudflared
   sops
   rbw
   pinentry-curses
   jq
   btop
   lazysql
   fastfetch
   cachix
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.tailscale.enable = true;


}
