#!/bin/bash

check_yes_no() {
  echo "$1"
  local ans
  PS3="> "
  select ans in Yes No; do
    [[ $ans == Yes ]] && eval "$1" && echo -e "[\e[92mOK\e[0m]" && return 0
    [[ $ans == No ]] && return 1
  done
}

confirm() {
  echo "$1"
  local ans
  PS3="> "
  select ans in Yes No; do
    [[ $ans == Yes ]] && return 0
    [[ $ans == No ]] && return 1
  done
}

if [ "$(whoami)" = root ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  RHEL_MAJOR=${VERSION_ID%%.*}

  #-------------------------------------------------------------------------------
  # UPDATE
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -y upgrade --refresh'
  check_yes_no 'dnf -q -y install net-tools'

  #-------------------------------------------------------------------------------
  # IPTABLES-SERVICES вместо firewalld
  #-------------------------------------------------------------------------------
  if confirm \
'Replace firewalld with iptables-services and install the default rules?'; then
    if dnf -q -y install iptables-services; then
      # Здесь НОВАЯ система, поэтому конфиг iptables просто перезатираем
      if cat >/etc/sysconfig/iptables <<'EOF'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# loopback
-A INPUT -i lo -j ACCEPT

# ICMP (ping)
-A INPUT -p icmp -j ACCEPT

# Разрешаем уже установленные и связанные соединения
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# SSH
-A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT

# Остальное — рубим
-A INPUT -j REJECT --reject-with icmp-host-prohibited

COMMIT
EOF
      then
        if dnf -q -y remove firewalld; then
          systemctl enable --now iptables && echo -e "[\e[92mOK\e[0m]"
        fi
      fi
    fi
  fi

  #-------------------------------------------------------------------------------
  # SELINUX (disable)
  #-------------------------------------------------------------------------------
  if confirm \
'Disable SELinux (setenforce 0 now and set SELINUX=disabled in config)?'; then
    if command -v setenforce &>/dev/null; then
      setenforce 0 || true
    fi
    if [ -f /etc/selinux/config ]; then
      sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    fi
  fi

  #-------------------------------------------------------------------------------
  # DISABLE IPV6 (via sysctl)
  #-------------------------------------------------------------------------------
  if confirm 'Disable IPv6 via sysctl?'; then
    cat >/etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system
  fi

  #-------------------------------------------------------------------------------
  # LOOSE REVERSE-PATH FILTERING (for VPN and asymmetric routing)
  #-------------------------------------------------------------------------------
  if confirm \
'Use loose IPv4 reverse-path filtering for VPN and asymmetric routing?'; then
    cat >/etc/sysctl.d/99-rp-filter.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 2
EOF
    sysctl --system
  fi

  #-------------------------------------------------------------------------------
  # REPOSITORIES (EPEL)
  #-------------------------------------------------------------------------------
  check_yes_no \
"dnf -q -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${RHEL_MAJOR}.noarch.rpm"

  #-------------------------------------------------------------------------------
  # TIME SYNC (Chrony)
  #-------------------------------------------------------------------------------
  check_yes_no 'ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime'
  check_yes_no 'dnf -q -y install chrony'
  check_yes_no 'systemctl enable --now chronyd'

  #-------------------------------------------------------------------------------
  # Python 3
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install python3 python3-devel python3-pip'

  #-------------------------------------------------------------------------------
  # NGINX
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install nginx'; then
    check_yes_no 'systemctl enable --now nginx'
    check_yes_no 'iptables -I INPUT -p tcp --dport 80 -j ACCEPT'
    check_yes_no 'iptables -I INPUT -p tcp --dport 443 -j ACCEPT'
    check_yes_no 'service iptables save'
  fi

  #-------------------------------------------------------------------------------
  # MariaDB
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install mariadb mariadb-server'; then
    check_yes_no 'systemctl enable --now mariadb'
  fi

  #-------------------------------------------------------------------------------
  # MongoDB (9.0 repo)
  #-------------------------------------------------------------------------------
  if confirm 'Configure the official MongoDB 9.0 repository?'; then
    if cat >/etc/yum.repos.d/mongodb-org-9.0.repo <<EOF
[mongodb-org-9.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$RHEL_MAJOR/mongodb-org/9.0/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-9.asc
EOF
    then
      echo -e "[\e[92mOK\e[0m]"
      check_yes_no 'dnf -q -y install mongodb-org'
      check_yes_no 'systemctl enable mongod --now'
    fi
  fi

  #-------------------------------------------------------------------------------
  # FAIL2BAN
  #-------------------------------------------------------------------------------
  if confirm 'Install Fail2Ban for SSH with iptables-services?'; then
    if dnf -q -y --setopt=install_weak_deps=False install \
      fail2ban-server fail2ban-systemd; then
      mkdir -p /etc/fail2ban/jail.d
      if cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[DEFAULT]
banaction = iptables-multiport
banaction_allports = iptables-allports
backend = systemd

[sshd]
enabled = true
EOF
      then
        if fail2ban-client -t; then
          systemctl enable --now fail2ban && echo -e "[\e[92mOK\e[0m]"
        fi
      fi
    fi
  fi

  #-------------------------------------------------------------------------------
  # SYSTEMD-JOURNAL LOG SIZE LIMITS
  #-------------------------------------------------------------------------------
  if confirm 'Limit systemd-journald log size?'; then
    mkdir -p /etc/systemd/journald.conf.d
    cat >/etc/systemd/journald.conf.d/limit-size.conf <<'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=20M
MaxRetentionSec=1month
EOF
    systemctl restart systemd-journald
  fi

  #-------------------------------------------------------------------------------
  # DEVELOPMENT TOOLS
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y groupinstall "Development Tools"'

  #---------------------------------------
  # Neovim (latest stable from GitHub)
  #---------------------------------------
  if confirm 'Установить последнюю версию Neovim из GitHub?'; then
    case $(uname -m) in
      x86_64) NVIM_ARCH=x86_64 ;;
      aarch64 | arm64) NVIM_ARCH=arm64 ;;
      *) NVIM_ARCH= ;;
    esac

    if [[ -z $NVIM_ARCH ]]; then
      echo "Unsupported architecture: $(uname -m)"
    elif NVIM_TMP=$(mktemp); then
      NVIM_DEST_TMP=/usr/local/bin/.nvim.new
      echo "[+] Скачиваю официальный Neovim AppImage для $NVIM_ARCH..."
      if curl -fL \
"https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.appimage" \
          -o "$NVIM_TMP" &&
        chmod +x "$NVIM_TMP" &&
        "$NVIM_TMP" --version >/dev/null 2>&1 &&
        install -m 0755 "$NVIM_TMP" "$NVIM_DEST_TMP" &&
        mv -f "$NVIM_DEST_TMP" /usr/local/bin/nvim &&
        ln -sf /usr/local/bin/nvim /usr/local/bin/vim; then
        rm -f /usr/local/bin/nvim-linux-x86_64.appimage \
          /usr/local/bin/nvim-linux-arm64.appimage
        echo "[+] Neovim установлен глобально как 'nvim' и 'vim'"
      else
        echo "[!] Не удалось скачать или проверить Neovim" >&2
      fi
      rm -f "$NVIM_TMP" "$NVIM_DEST_TMP"
    fi
  fi

  #-------------------------------------------------------------------------------
  # OTHER UTILITIES
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install open-vm-tools'
  check_yes_no 'dnf -q -y install wget'
  check_yes_no 'dnf -q -y install nano'
  check_yes_no 'dnf -q -y install rsync'
  check_yes_no 'dnf -q -y install mc'
  check_yes_no 'dnf -q -y install tmux'
  check_yes_no 'dnf -q -y install plocate && updatedb'
  check_yes_no 'dnf -q -y install httpd-tools'
  check_yes_no 'dnf -q -y install lrzsz'
  check_yes_no 'dnf -q -y install s-nail'
  check_yes_no 'dnf -q -y install ripgrep'
  check_yes_no 'dnf -q -y remove cockpit'
fi

#-------------------------------------------------------------------------------
# DOTFILES / CONFIGS (user)
#-------------------------------------------------------------------------------
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/red-hat-starter-kit/refs/heads/main/.bashrc -o ~/.bashrc'
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/red-hat-starter-kit/refs/heads/main/.tmux.conf -o ~/.tmux.conf'
