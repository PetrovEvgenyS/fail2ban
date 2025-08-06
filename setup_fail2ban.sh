#!/bin/bash

# --- Установка переменных ---
FAIL2BAN_CONF_DIR="/etc/fail2ban"           # Директория конфигурации Fail2Ban
JAIL_LOCAL="$FAIL2BAN_CONF_DIR/jail.local"  # Основной файл конфигурации
JAIL_D_DIR="$FAIL2BAN_CONF_DIR/jail.d"      # Директория для jails
BANTIME="1h"            # Время блокировки
FINDTIME="10m"          # Период анализа логов
MAXRETRY=5              # Максимум попыток
ALLOWED_IPS="127.0.0.1/8 ::1 10.100.10.0/24" # Разрешённые IP/подсети


# ---------------------------------------------------------------------------------------


# --- Проверка запуска через sudo ---
if [ -z "$SUDO_USER" ]; then
    echo "Пожалуйста, запустите скрипт через sudo."
    exit 1
fi

# --- Функция для проверки и установки пакетов ---
install_packages() {
    echo "Проверка и установка необходимых пакетов..."
    if ! rpm -q epel-release > /dev/null; then
        dnf install -y epel-release || { echo "Ошибка установки epel-release" >&2; exit 1; }
    fi
    dnf install -y fail2ban fail2ban-firewalld || { echo "Ошибка установки Fail2Ban" >&2; exit 1; }
    echo "Пакеты установлены"
}

# --- Проверка и запуск firewalld ---
configure_firewalld() {
    echo "Настройка firewalld..."
    if ! systemctl is-active --quiet firewalld; then
        systemctl start firewalld || { echo "Ошибка запуска firewalld" >&2; exit 1; }
        systemctl enable firewalld
    fi
    echo "firewalld работает"
}

# --- Создание базовой конфигурации Fail2Ban ---
configure_fail2ban() {
    echo "Создание конфигурации Fail2Ban..."

    # --- Создание директории jail.d, если не существует ---
    mkdir -p "$JAIL_D_DIR"

    # --- Настройка глобальных параметров в jail.local ---
    cat > "$JAIL_LOCAL" << EOF
[DEFAULT]
# Глобальные настройки Fail2Ban

ignoreip = $ALLOWED_IPS
bantime = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
backend = auto
banaction = firewallcmd-ipset
# action = %(action_mw)s
# destemail = admin@example.com
# sendername = Fail2Ban
# mta = sendmail
EOF

    # --- Настройка SSH jail ---
    cat > "$JAIL_D_DIR/sshd.conf" << EOF
[sshd]
enabled = true
port = ssh
logpath = /var/log/secure
maxretry = $MAXRETRY
bantime = $BANTIME
findtime = $FINDTIME
EOF

    # --- Проверка синтаксиса конфигурации ---
    fail2ban-client -t || { echo "Ошибка в конфигурации Fail2Ban" >&2; exit 1; }
    echo "Конфигурация создана"
}

# --- Запуск и проверка Fail2Ban ---
start_fail2ban() {
    echo "Запуск Fail2Ban..."
    systemctl restart fail2ban || { echo "Ошибка перезапуска Fail2Ban" >&2; exit 1; }
    systemctl enable fail2ban
    sleep 5
    if ! fail2ban-client status > /dev/null; then
        echo "Ошибка: Fail2Ban не запустился" >&2
        exit 1
    fi
    echo "Fail2Ban запущен. Статус:"
    fail2ban-client status
}

# # --- Проверка SELinux (если включён) ---
# configure_selinux() {
#     if command -v getenforce > /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
#         echo "Настройка SELinux для Fail2Ban..."
#         setsebool -P httpd_can_network_connect 1
#         setsebool -P sshd_can_network_connect 1
#     fi
# }

# --- Тестирование и логирование ---
test_setup() {
    echo "Проверка настроенных jails..."
    for jail in sshd apache-auth; do
        if [ -f "$JAIL_D_DIR/$jail.conf" ]; then
            fail2ban-client status "$jail" && echo "Jail $jail активен"
        fi
    done
    echo "Логи Fail2Ban: /var/log/fail2ban.log"
}

# --- Основной процесс ---
main() {
    install_packages
    configure_firewalld
    #configure_selinux
    configure_fail2ban
    start_fail2ban
    test_setup
    echo "Настройка Fail2Ban завершена успешно."
}

main

# --- Инструкции по использованию ---
echo "Для проверки логов: tail -f /var/log/fail2ban.log"
echo "Для проверки статуса: fail2ban-client status"
echo "Для ручной блокировки IP: fail2ban-client set sshd banip <IP>"
echo "Для разблокировки IP: fail2ban-client set sshd unbanip <IP>"