{ config, lib, pkgs, ... } : {
  options = {
    nix-tun.yubikey-gpg.enable = lib.mkEnableOption "Enable Yubikey and GPG Support";
  };

  config = lib.mkIf config.jamesofscout.yubikey-gpg.enable {

    environment.systemPackages = with pkgs; [
      yubikey-personalization
      gnupg
    ];
    services.udev.packages = with pkgs; [
      yubikey-personalization
    ];

    programs.gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      enableSSHSupport = true;
    };

    # Use GPG Agent instead of SSH Agent
    programs.ssh.startAgent = lib.mkIf config.services.openssh.enable false;
    environment.shellInit = lib.mkIf config.services.openssh.enable ''
      gpg-connect-agent /bye
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
      echo UPDATESTARTUPTTY | gpg-connect-agent
    '';

  };
  
}
