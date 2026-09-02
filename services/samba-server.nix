{ lib, config, pkgs, ... }: {
  options = {
    nix-tun.services.samba-dc = {
      enable = lib.mkEnableOption "Enable Samba DC Service";
      workgroup = lib.mkOption {
        type = lib.types.str;
        description = "Sets the windows workgroup, has a maximum length of 15 characters";
        default = "WORKGROUP";
      };
      domain = lib.mkOption {
        type = lib.types.str;
        description = "The Kerberos/AD Domain";
        defaultText = "config.networking.domain";
      };
      primary = lib.mkOption {
        type = lib.types.bool;
      };
      acme = {
        enable = lib.mkEnableOption "Enable ACME";
      };
      dns = {
        forwarders = lib.mkOption {
          description = "The DNS servers to be used for requests not belonging to the domain";
          type = lib.types.listOf lib.types.str;
        };
        dnssec-validation = lib.mkOption {
          description = "The dnssec-validation option in bind";
          default = "no";
          type = lib.types.str;
        };
      };
    };
  };

  config = (lib.mkIf config.nix-tun.services.samba-dc.enable) (
    let cfg = config.nix-tun.services.samba-dc;
    in {
      nix-tun.utils.containers.samba-dc = {
        volumes = {
          "/var/kea" = {
            owner = "kea";
          };
        };
        secrets = {
          "dhcpduser.leytab" = {
            owner = "kea";
          };
        };

        config = { ... }: {
          security.pam.krb5.enable = false;

          environment.systemPackages = [
            pkgs.dig.out
            pkgs.dnsutils
          ];

          security.acme = lib.mkIf cfg.acme.enable {
            certs.samba.extraDomainNames = [ cfg.domain ];
          };

          systemd.services.kea-dhcp4-server.serviceConfig.DynamicUser = lib.mkForce false;

          users.users.kea = {
            isSystemUser = true;
            group = "kea";
          };
          users.groups.kea = { };
          services.kea = lib.mkIf cfg.dhcp.enable {
            # DDNS via DHCP, with kerberos Authentication
            # Following the example at: https://kea.readthedocs.io/en/kea-2.7.5/arm/integrations.html#gss-tsig
            dhcp-ddns = {
              enable = true;
              settings = {
                # IP + Port for NameChange Requests 
                ip-address = "127.0.0.1";
                port = 53001;
                forward-ddns = {
                  ddns-domains = [
                    {
                      name = cfg.domain;
                      comment = "DDNS for ${cfg.domain}";
                      dns-servers = [
                        {
                          ip-address = "127.0.0.1";
                        }
                      ];
                    }
                  ];
                };

                reverse-ddns = {
                  ddns-domains = [
                    {
                      name = "154.99.134.in-addr.arpa";
                      dns-servers = [
                        {
                          ip-address = "127.0.0.1";
                        }
                      ];
                    }
                  ];
                };

                hooks-libraries = [
                  {
                    library = "${pkgs.kea}/lib/kea/hooks/libddns_gss_tsig.so";
                    parameters = {
                      server-principal = "dhcpduser@${cfg.domain}";
                      client-principal = "dhcpduser@${cfg.domain}";
                      client-keytab = "FILE:/secrets/"; # toplevel only
                      gss-replay-flag = true; # GSS anti replay service
                      gss-sequence-flag = false; #no GSS sequence service
                      tkey-lifetime = 3600; # 1 hour
                      rekey-interval = 2700; # 45 minutes
                      retry-interval = 120; # 2 minutes
                      tkey-protocol = "TCP";
                      fallback = false;
                      servers = [
                        {
                          id = "localhost";
                          ip-address = "127.0.0.1";
                          port = 53;
                        }
                      ];
                    };
                  }
                ];
              };
            };

            dhcp4 = {
              enable = true;
              settings = {
                valid-lifetime = 4000;
                renew-timer = 1000;
                rebind-timer = 2000;

                dhcp-ddns = {
                  "enable-updates" = true;
                  "server-ip" = "127.0.0.1";
                  "server-port" = 53001;
                  "sender-ip" = "";
                  "sender-port" = 0;
                  "max-queue-size" = 1024;
                  "ncr-protocol" = "UDP";
                  "ncr-format" = "JSON";
                };

                interfaces-config = {
                  interfaces = [
                    "eth0"
                  ];
                };

                lease-database = {
                  name = "/var/lib/kea/dhcp4.leases";
                  persist = true;
                  type = "memfile";
                };

                subnet4 = [
                  {
                    id = 1;
                    option-data = [
                      {
                        name = "domain-name-servers";
                        csv-format = true;
                        data = lib.strings.concatStringsSep ", " cfg.dc.dhcp.dns-servers;
                      }
                      {
                        name = "routers";
                        csv-format = true;
                        data = lib.strings.concatStringsSep ", " cfg.dc.dhcp.routers;
                      }
                      {
                        name = "time-servers";
                        csv-format = true;
                        data = lib.strings.concatStringsSep ", " cfg.dc.dhcp.time-servers;
                      }
                      {
                        name = "domain-name";
                        data = cfg.domain;
                      }
                    ];
                    pools = [
                      {
                        pool = cfg.dc.dhcp.pool;
                      }
                    ];
                    subnet = cfg.dc.dhcp.subnet;
                    reservations = import ./dhcp.nix;
                  }
                ];
              };
            };
          };
          services.bind = {
            enable = true;

            cacheNetworks = [
              "127.0.0.0/8"
            ];

            ipv4Only = false;
            forwarders = cfg.dns.forwarders;
            extraOptions = ''
              allow-update {
                none;
              };
              dnssec-validation ${cfg.dc.dns.dnssec-validation};
              minimal-responses yes;
            '';

            extraConfig = ''
              include "/var/lib/samba/bind-dns/named.conf";
            '';
          };

          systemd.services.bind = {
            serviceConfig = {
              ReadWritePaths = [ "/var/lib/samba/bind-dns" ];
            };
            environment = {
              # Fixes a Segfault in bind + samba 4.20.* see: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1074378
              LDB_MODULES_DISABLE_DEEPBIND = "true";
            };
          };

          # Disable default Samba `smbd` service, we will be using the `samba` server binary
          # Because the normal service can not be used for a dc
          systemd.services.samba = {
            restartTriggers = [
              config.environment.etc."samba/smb.conf".source
            ];
            description = "Samba Service Daemon";

            script = ''
              ${pkgs.samba4Full}/sbin/samba --foreground --no-process-group
            '';

            requires = lib.mkIf cfg.acme.enable [
              "acme-samba.service"
            ];

            requiredBy = [
              "samba.target"
            ];
            partOf = [
              "samba.target"
            ];

            serviceConfig = {
              ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
              LimitNOFILE = 16384;
              PIDFile = "/run/samba.pid";
              Type = "notify";
              NotifyAccess = "all"; #may not do anything...
            };
            unitConfig.RequiresMountsFor = "/var/lib/samba";
          };

          services.samba = {
            enable = true;
            winbindd.enable = false;
            smbd.enable = false;
            nmbd.enable = false;
            package = pkgs.samba4Full;
            openFirewall = true;

            settings = {
              global = {
                "server role" = "active directory domain controller";
                "ad dc functional level" = "2016";
                "server services" = "s3fs, rpc, ldap, cldap, kdc, drepl, winbindd, ntp_signd, kcc, dnsupdate";
                "allow dcerpc auth level connect" = "no";
                "netbios name" = cfg.hostname;
                "restrict anonymous" = 2;
                "log level" = "0";
                "disable netbios" = "yes";
                "realm" = cfg.domain;
                "workgroup" = cfg.workgroup;
                "tls keyfile" = "tls/key.pem";
                "tls certfile" = "tls/cert.pem";
                "tls cafile" = if cfg.acme.enable then "" else "tls/ca.pem";
                "idmap_ldb:use rfc2307" = "yes";
                "additional dns hostnames" = cfg.domain;
                "nsupdate command" = "${pkgs.dnsutils}/bin/nsupdate -g";
              };
              sysvol = {
                path = "/var/lib/samba/sysvol";
                "read only" = if cfg.dc.primary then "no" else "yes";
              };
              netlogon = {
                path = "/var/lib/samba/sysvol/${cfg.domain}/scripts";
                "read only" = if cfg.dc.primary then "no" else "yes";
              };
            };
          };

          networking = {
            resolvconf.enable = false;
            # Ports for a samba dc
            firewall = {
              allowedTCPPorts = [
                53 # DNS
                88 # Kerberos
                123 # ntp
                135 # End Point Mapper
                139 # NetBIOS Session
                389 # LDAP
                445 # SMB over TCP
                464 # Kerberos kpasswd/
                636 # LDAPS
                953 # DNS
                3268 # Global Catalog
                3269 # Global Catalog SSL
              ];

              # Dynamic RPC Ports
              allowedTCPPortRanges = [
                {
                  from = 49152;
                  to = 65535;
                }
              ];

              allowedUDPPorts = [
                53 # DNS
                88 # Kerberos
                123 # ntp
                137 # NetBIOS Name Service
                138 # NetBIOS Datagram
                389 # LDAP
                464 # Kerberos kpasswd
              ];
            };
          };

        };
      };
    }
  );
}
