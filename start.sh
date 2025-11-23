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

if [ "$(whoami)" = root ]; then
  # Update system packages
  check_yes_no 'dnf -y upgrade --refresh' # use dnf instead of yum
  check_yes_no 'dnf -q -y install net-tools'

  #-------------------------------------------------------------------------------
  # IPTABLES (replace firewalld with iptables service)
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y remove firewalld'
  check_yes_no 'dnf -q -y install iptables-services iptables-utils'
  check_yes_no 'systemctl enable iptables --now'

  #-------------------------------------------------------------------------------
  # DISABLE IPV6 (via sysctl)
  #-------------------------------------------------------------------------------
  if check_yes_no 'Disable IPv6 via sysctl?'; then
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
  # Use Remi repo appropriate for the OS version (e.g. 9 or 8)
  check_yes_no 'dnf -q -y install http://rpms.remirepo.net/enterprise/remi-release-9.rpm'

  #-------------------------------------------------------------------------------
  # TIME SYNC (Chrony)
  #-------------------------------------------------------------------------------
  check_yes_no 'ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime'
  check_yes_no 'dnf -q -y install chrony'
  check_yes_no 'systemctl enable chronyd'
  check_yes_no 'systemctl start chronyd'

  #-------------------------------------------------------------------------------
  # Python 3 (already default on Alma/Rocky, ensure installed)
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install python3 python3-devel python3-pip'

  #-------------------------------------------------------------------------------
  # NGINX
  #-------------------------------------------------------------------------------
  if check_yes_no 'dnf -q -y install nginx'; then
    check_yes_no 'systemctl enable nginx'
    check_yes_no 'systemctl start nginx'
    check_yes_no 'iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT'
    check_yes_no 'iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT'
    check_yes_no 'service iptables save'
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
  # MongoDB (update to newer MongoDB repository, e.g., 6.0)
  #-------------------------------------------------------------------------------
  if check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/mongodb-org-6.0.repo -o /etc/yum.repos.d/mongodb-org-6.0.repo'; then
    check_yes_no 'dnf -q -y install mongodb-org'
    check_yes_no 'systemctl enable mongod --now'
    # Disable transparent hugepages (if needed by MongoDB)
    echo 'echo "never" > /sys/kernel/mm/transparent_hugepage/enabled' >>/etc/rc.local
    echo 'echo "never" > /sys/kernel/mm/transparent_hugepage/defrag' >>/etc/rc.local
    check_yes_no 'chmod +x /etc/rc.d/rc.local'
    echo "To disable monitoring reminder in MongoDB shell: db.disableFreeMonitoring()"
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
  if check_yes_no 'Limit systemd-journald log size?'; then
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
  if check_yes_no 'Установить последнюю версию Neovim из GitHub?'; then
    cd /usr/local/bin

    echo "[+] Скачиваю Neovim AppImage..."
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage

    chmod +x nvim-linux-x86_64.appimage

    # Переименовываем в nvim и vim
    ln -sf /usr/local/bin/nvim-linux-x86_64.appimage /usr/local/bin/nvim
    ln -sf /usr/local/bin/nvim-linux-x86_64.appimage /usr/local/bin/vim

    echo "[+] Neovim установлен глобально как 'nvim' и 'vim'"
  fi

  #-------------------------------------------------------------------------------
  # NEOVIM Integration
  #-------------------------------------------------------------------------------
  check_yes_no 'dnf -q -y install python3-neovim' # Python support for Neovim (pynvim)
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
  # FZF (for Vim) and .gitignore plugin dependency:
  check_yes_no 'dnf -q -y install the_silver_searcher'
  check_yes_no 'pip3 install -q -U autopep8'
  check_yes_no 'pip3 install -q -U neovim'
  # Remove unwanted default packages
  check_yes_no 'dnf -q -y remove cockpit'
fi

# Fetch configuration files to set up shell and editors
check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/red-hat-starter-kit/refs/heads/main/.bashrc -o ~/.bashrc'
check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.ctags -o ~/.ctags'
check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.tern-project -o ~/.tern-project'
check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.tmux.conf -o ~/.tmux.conf'
check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.pylintrc -o ~/.pylintrc'
check_yes_no 'curl -fLo ~/.config/nvim/init.vim --create-dirs https://raw.githubusercontent.com/Rilkener/mypost/master/init.vim'

#-------------------------------------------------------------------------------
# Randomized colorful Bash prompt (optional)
#-------------------------------------------------------------------------------
R=($(shuf -i31-37 -n5))
BASHRC=$(
  cat <<-END
export PS1='\[\033[01;${R[0]}m\]\u\[\033[01;${R[1]}m\]@\[\033[01;${R[2]}m\]\h \[\033[01;${R[3]}m\]\w \[\033[01;${R[4]}m\]$ \[\033[00m\]'
END
)
if check_yes_no 'echo "Add color to .bashrc?"'; then
  echo "$BASHRC" >>~/.bashrc
  #exec bash # (cannot source .bashrc in a non-interactive script)
fi

# Install vim-plug for Neovim
check_yes_no 'curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# Python virtual environment for Neovim plugins and linters
if check_yes_no 'python3 -m venv env'; then
  check_yes_no 'echo ". env/bin/activate" >> ~/.bashrc'
  # Activate the venv in this script context:
  . env/bin/activate
  check_yes_no 'pip install -q -U autopep8'
  check_yes_no 'pip install -q -U neovim'
  check_yes_no 'pip install -q -U pynvim'
  check_yes_no 'pip install -q -U "python-lsp-server[all]"'
fi

# Enable true color in Vim (if MYCOLOR is set, some vimrc may use it)
check_yes_no 'echo "export MYCOLOR=24bit" >> ~/.bash_profile'

# Global ESLint configuration (optional)
echo "Global ESLint setup (not needed for React projects, which have local config)."
read -p "Configure global ESLint now? (y/n) " CONT
if [ "$CONT" = "y" ]; then
  check_yes_no 'npm init -y'
  check_yes_no 'npm install eslint --save-dev'
  echo "Choose 'To check syntax, find problems, and enforce code style' when prompted."
  check_yes_no 'eslint --init'
  check_yes_no 'curl -s https://raw.githubusercontent.com/Rilkener/mypost/master/.eslintrc.js -o ~/.eslintrc.js'
fi
