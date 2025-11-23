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
  #-------------------------------------------------------------------------------
  # UPDATE
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -y upgrade --refresh'
  check_yes_no 'dnf -q -y install net-tools'

  #-------------------------------------------------------------------------------
  # IPTABLES вместо firewalld + свой сервис + "service iptables save"
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y remove firewalld'
  check_yes_no 'dnf -q -y install iptables iptables-utils'

  # Базовый конфиг правил, если его ещё нет
  if [ ! -f /etc/sysconfig/iptables ]; then
    cat >/etc/sysconfig/iptables <<'EOF'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
EOF
  fi

  # systemd-юнит для iptables-restore
  cat >/etc/systemd/system/iptables-restore.service <<'EOF'
[Unit]
Description=Restore iptables firewall rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/sysconfig/iptables
ExecReload=/usr/sbin/iptables-restore /etc/sysconfig/iptables
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  check_yes_no 'systemctl daemon-reload'
  check_yes_no 'systemctl enable iptables-restore.service --now'

  # Компактный /etc/init.d/iptables из твоего репозитория
  check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/red-hat-starter-kit/refs/heads/main/iptables -o /etc/init.d/iptables'
  check_yes_no 'chmod +x /etc/init.d/iptables'

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
  # REPOSITORIES (EPEL and Remi)
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install epel-release'
  check_yes_no \
'dnf -q -y install http://rpms.remirepo.net/enterprise/remi-release-9.rpm'

  #-------------------------------------------------------------------------------
  # TIME SYNC (Chrony)
  #-------------------------------------------------------------------------------
  check_yes_no 'ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime'
  check_yes_no 'dnf -q -y install chrony'
  check_yes_no 'systemctl enable chronyd'
  check_yes_no 'systemctl start chronyd'

  #-------------------------------------------------------------------------------
  # Python 3
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install python3 python3-devel python3-pip'

  #-------------------------------------------------------------------------------
  # NGINX
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install nginx'; then
    check_yes_no 'systemctl enable nginx'
    check_yes_no 'systemctl start nginx'
    check_yes_no \
'iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT'
    check_yes_no \
'iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT'
    # Сохраняем текущие правила, чтобы поднялись после ребута
    check_yes_no 'iptables-save >/etc/sysconfig/iptables'
    check_yes_no 'systemctl reload iptables-restore.service'
  fi

  #-------------------------------------------------------------------------------
  # MariaDB + PhpMyAdmin
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install mariadb mariadb-server'; then
    check_yes_no 'systemctl enable mariadb'
    check_yes_no 'systemctl start mariadb'
    check_yes_no 'dnf -q -y install phpmyadmin'
  fi

  #-------------------------------------------------------------------------------
  # MongoDB (6.0 repo)
  #-------------------------------------------------------------------------------
  if check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/mongodb-org-6.0.repo -o /etc/yum.repos.d/mongodb-org-6.0.repo'; then
    check_yes_no 'dnf -q -y install mongodb-org'
    check_yes_no 'systemctl enable mongod --now'

    # Disable transparent hugepages через rc.local
    if [ ! -f /etc/rc.d/rc.local ]; then
      touch /etc/rc.d/rc.local
    fi
    chmod +x /etc/rc.d/rc.local
    if ! grep -q 'transparent_hugepage/enabled' /etc/rc.d/rc.local; then
      cat >>/etc/rc.d/rc.local <<'EOF'
echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
echo "never" > /sys/kernel/mm/transparent_hugepage/defrag
EOF
    fi

    echo \
"To disable monitoring reminder in MongoDB shell: db.disableFreeMonitoring()"
  fi

  #-------------------------------------------------------------------------------
  # FAIL2BAN
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install fail2ban'; then
    check_yes_no 'systemctl enable fail2ban'
    check_yes_no 'systemctl start fail2ban'
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

  #-------------------------------------------------------------------------------
  # Node.js and NPM Global Packages
  #-------------------------------------------------------------------------------
  echo 'Installing formatters and linters used by nvim...'
  check_yes_no 'npm install -g tern'
  check_yes_no 'npm install -g eslint'
  echo 'Installing js, html, json beautifier...'
  check_yes_no 'npm install -g js-beautify'

  #---------------------------------------
  # Neovim (последняя версия с GitHub)
  #---------------------------------------
  if confirm 'Установить последнюю версию Neovim из GitHub?'; then
    cd /usr/local/bin
    echo "[+] Скачиваю Neovim AppImage..."
    curl -LO \
https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
    chmod +x nvim-linux-x86_64.appimage
    ln -sf /usr/local/bin/nvim-linux-x86_64.appimage /usr/local/bin/nvim
    ln -sf /usr/local/bin/nvim-linux-x86_64.appimage /usr/local/bin/vim
    echo "[+] Neovim установлен глобально как 'nvim' и 'vim'"
  fi

  #-------------------------------------------------------------------------------
  # NEOVIM Integration
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install python3-neovim'
  check_yes_no 'npm install -g neovim'

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
  check_yes_no 'dnf -q -y install mailx'
  check_yes_no 'pip3 install -q -U virtualenv'
  check_yes_no 'dnf -q -y install the_silver_searcher'
  check_yes_no 'pip3 install -q -U autopep8'
  check_yes_no 'pip3 install -q -U neovim'
  check_yes_no 'dnf -q -y remove cockpit'
fi

#-------------------------------------------------------------------------------
# DOTFILES / CONFIGS (для текущего пользователя, не обязательно root)
#-------------------------------------------------------------------------------
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/red-hat-starter-kit/refs/heads/main/.bashrc -o ~/.bashrc'
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.ctags -o ~/.ctags'
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.tern-project -o ~/.tern-project'
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.tmux.conf -o ~/.tmux.conf'
check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.pylintrc -o ~/.pylintrc'
check_yes_no \
'curl -fLo ~/.config/nvim/init.vim --create-dirs https://raw.githubusercontent.com/Rilkener/mypost/master/init.vim'

#-------------------------------------------------------------------------------
# Randomized colorful Bash prompt (optional)
#-------------------------------------------------------------------------------
R=($(shuf -i31-37 -n5))
BASHRC=$(
  cat <<-END
export PS1='\[\033[01;${R[0]}m\]\u\[\033[01;${R[1]}m\]@\[\033[01;${R[2]}m\]\h \[\033[01;${R[3]}m\]\w \[\033[01;${R[4]}m\]$ \[\033[00m\]'
END
)
if confirm 'Add color to .bashrc?'; then
  echo "$BASHRC" >>~/.bashrc
fi

#-------------------------------------------------------------------------------
# vim-plug for Neovim
#-------------------------------------------------------------------------------
check_yes_no \
'curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

#-------------------------------------------------------------------------------
# Python virtual environment for Neovim plugins and linters
#-------------------------------------------------------------------------------
if check_yes_no 'python3 -m venv env'; then
  check_yes_no 'echo ". env/bin/activate" >> ~/.bashrc'
  . env/bin/activate
  check_yes_no 'pip install -q -U autopep8'
  check_yes_no 'pip install -q -U neovim'
  check_yes_no 'pip install -q -U pynvim'
  check_yes_no 'pip install -q -U "python-lsp-server[all]"'
fi

#-------------------------------------------------------------------------------
# True color for Vim
#-------------------------------------------------------------------------------
check_yes_no 'echo "export MYCOLOR=24bit" >> ~/.bash_profile'

#-------------------------------------------------------------------------------
# Global ESLint configuration (optional)
#-------------------------------------------------------------------------------
echo \
"Global ESLint setup (not needed for React projects, which have local config)."
read -p "Configure global ESLint now? (y/n) " CONT
if [ "$CONT" = "y" ]; then
  check_yes_no 'npm init -y'
  check_yes_no 'npm install eslint --save-dev'
  echo \
"Choose 'To check syntax, find problems, and enforce code style' when prompted."
  check_yes_no \
'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.eslintrc.js -o ~/.eslintrc.js'
fi
