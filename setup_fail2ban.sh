#!/bin/bash

# --- Установка переменных ---
FAIL2BAN_CONF_DIR="/etc/fail2ban"           # Директория конфигурации Fail2Ban
JAIL_LOCAL="$FAIL2BAN_CONF_DIR/jail.local"  # Основной файл конфигурации
JAIL_D_DIR="$FAIL2BAN_CONF_DIR/jail.d"      # Директория для jails
BANTIME="1h"            # Время блокировки
FINDTIME="10m"          # Период анализа логов
MAXRETRY=5              # Максимум попыток
ALLOWED_IPS="127.0.0.1/8 ::1 10.100.10.0/24" # Разрешённые IP/подсети

### ЦВЕТА ###
ESC=$(printf '\033') RESET="${ESC}[0m" MAGENTA="${ESC}[35m" RED="${ESC}[31m" GREEN="${ESC}[32m"

### Функции цветного вывода ###
magentaprint() { echo; printf "${MAGENTA}%s${RESET}\n" "$1"; }
errorprint() { echo; printf "${RED}%s${RESET}\n" "$1"; }
greenprint() { echo; printf "${GREEN}%s${RESET}\n" "$1"; }


# ---------------------------------------------------------------------------------------


# --- Проверка запуска через sudo ---
if [ -z "$SUDO_USER" ]; then
    errorprint "Пожалуйста, запустите скрипт через sudo."
    exit 1
fi

# --- Функция для проверки и установки пакетов ---
install_packages() {
    magentaprint "Проверка и установка необходимых пакетов..."
    if ! rpm -q epel-release > /dev/null; then
        dnf install -y epel-release || { errorprint "Ошибка установки epel-release" >&2; exit 1; }
    fi
    dnf install -y fail2ban fail2ban-firewalld || { errorprint "Ошибка установки Fail2Ban" >&2; exit 1; }
    greenprint "Пакеты установлены"
}

# --- Проверка и запуск firewalld ---
configure_firewalld() {
    magentaprint "Настройка firewalld..."
    if ! systemctl is-active --quiet firewalld; then
        systemctl start firewalld || { errorprint "Ошибка запуска firewalld" >&2; exit 1; }
        systemctl enable firewalld
    fi
    greenprint "firewalld работает"
}

# --- Создание базовой конфигурации Fail2Ban ---
configure_fail2ban() {
    magentaprint "Создание конфигурации Fail2Ban..."

    # --- Создание директории jail.d, если не существует ---
    mkdir -p "$JAIL_D_DIR"

    # --- Настройка глобальных параметров в jail.local ---
    cat > "$JAIL_LOCAL" << EOF
[DEFAULT]
# Глобальные настройки Fail2Ban

ignoreip = $ALLOWED_IPS        # IP-адреса/подсети, которые не будут блокироваться
bantime = $BANTIME             # Время блокировки IP
findtime = $FINDTIME           # Период, за который считаются неудачные попытки
maxretry = $MAXRETRY           # Количество неудачных попыток до блокировки
backend = auto                 # Механизм чтения логов (auto - автоматически)
banaction = firewallcmd-ipset  # Действие при блокировке (firewalld через ipset)
# action = %(action_mw)s       # Альтернативное действие (например, с уведомлением)
# destemail = admin@example.com # Email для уведомлений
# sendername = Fail2Ban        # Имя отправителя уведомлений
# mta = sendmail               # Почтовый транспорт для отправки писем
EOF

    # --- Настройка SSH jail ---
    cat > "$JAIL_D_DIR/sshd.conf" << EOF
[sshd]
enabled = true                 # Включить защиту для SSH
port = ssh                     # Порт для мониторинга (обычно ssh)
logpath = /var/log/secure      # Путь к логу SSH
maxretry = $MAXRETRY           # Количество неудачных попыток до блокировки
bantime = $BANTIME             # Время блокировки IP
findtime = $FINDTIME           # Период, за который считаются неудачные попытки
EOF

    # --- Проверка синтаксиса конфигурации ---
    fail2ban-client -t || { errorprint "Ошибка в конфигурации Fail2Ban" >&2; exit 1; }
    greenprint "Конфигурация создана"
}

# --- Запуск и проверка Fail2Ban ---
start_fail2ban() {
    magentaprint "Запуск Fail2Ban..."
    systemctl restart fail2ban || { errorprint "Ошибка перезапуска Fail2Ban" >&2; exit 1; }
    systemctl enable fail2ban
    sleep 5
    if ! fail2ban-client status > /dev/null; then
        errorprint "Ошибка: Fail2Ban не запустился" >&2
        exit 1
    fi
    magentaprint "Fail2Ban запущен. Статус:"
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
    magentaprint "Проверка настроенных jails..."
    for jail in sshd apache-auth; do
        if [ -f "$JAIL_D_DIR/$jail.conf" ]; then
            fail2ban-client status "$jail" && greenprint "Jail $jail активен"
        fi
    done
}

# --- Основной процесс ---
main() {
    install_packages
    configure_firewalld
    #configure_selinux
    configure_fail2ban
    start_fail2ban
    test_setup
    greenprint "Настройка Fail2Ban завершена успешно."
}

main

# --- Инструкции по использованию ---
magentaprint "Инструкции по использованию Fail2Ban:"
echo "Для проверки логов: tail -f /var/log/fail2ban.log"
echo "Для проверки статуса: fail2ban-client status"
echo "Для ручной блокировки IP: fail2ban-client set sshd banip <IP>"
echo "Для разблокировки IP: fail2ban-client set sshd unbanip <IP>"