# ~/.bashrc  — compact, sane defaults

# 1) Глобальный bashrc
[[ -f /etc/bashrc ]] && . /etc/bashrc

# 2) Только для интерактивной сессии
[[ $- != *i* ]] && return

# 3) Базовое окружение
export EDITOR=nvim
export VISUAL=nvim
# Разрешить Ctrl+S/Ctrl+Q только в терминале
[[ -t 0 ]] && stty -ixon

# 4) История: больше, без дублей, автосинхронизация между сессиями
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL=ignoreboth:erasedups   # убирает дубликаты и команды с пробелом
export HISTIGNORE="ls:ps:history:fg:bg:exit:clear"
shopt -s histappend                        # не затирать историю
shopt -s cmdhist                           # сохранять многострочные как одну
# -a: дописать новые, -n: дочитать то, что записали другие сессии
PROMPT_COMMAND='history -a; history -n; '"$PROMPT_COMMAND"

# 5) Подсветка man/less (безопаснее и переносимее)
# less умеет цвета через LESS_TERMCAP_* (подсветка форматирования man).
# mb=blink, md=bold, so=standout, us=underline; *e = reset
export LESS='-R'   # пропускать ANSI-цвета
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'
export LESS_TERMCAP_ue=$'\e[0m'
# lesspipe даст синтакс-хайлайт для многих форматов (если установлен)
if command -v lesspipe >/dev/null 2>&1; then
  eval "$(SHELL=/bin/sh lesspipe)"
fi

# 6) Подсказки оболочки
shopt -s checkwinsize       # корректная ширина терминала
shopt -s autocd             # 'cd' по названию директории
shopt -s cdspell dirspell   # автопочинка опечаток в cd
shopt -s globstar           # ** рекурсивные глоб-шаблоны

# 7) Алиасы
alias dusk='du -ahd1 | sort -rh | head -11'
alias vim='nvim'

# 8) fzf с уважением .gitignore и приятной темой
# Лучше задавать опции через переменную, а не заменять саму команду alias’ом
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
export FZF_DEFAULT_OPTS="--height=40% --layout=reverse \
  --color=fg:#839496,fg+:#93a1a1,bg:#002b36,bg+:#073642,hl:#b58900,hl+:#b58900"

# Команда по-умолчанию: fd -> rg -> ag (что установлено)
if command -v fd >/dev/null 2>&1; then
  # fd сам по себе уважает .gitignore и скрытые при флагах ниже
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
elif command -v rg >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'
elif command -v ag >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='ag -g ""'
fi
# Те же источники для Ctrl-T и Alt-C
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git 2>/dev/null || rg --hidden --glob "!.git" --files -S 2>/dev/null | xargs -r dirname | sort -u'

# 9) Подсказка/цветной prompt (оставил твой стиль)
PS1='\[\e[01;35m\]\u\[\e[01;37m\]@\[\e[01;33m\]\h \[\e[01;34m\]\w \[\e[01;36m\]\$ \[\e[0m\]'

# 10) Python venv
# Не активируй "env/bin/activate" глобально — это ломает любые не-проектные шеллы.
# Лучше direnv/pyenv (автоактивация по каталогу проекта).
# Если очень нужно авто-активировать локальную venv с именем .venv:
if [[ -f .venv/bin/activate ]]; then
  . .venv/bin/activate
fi
