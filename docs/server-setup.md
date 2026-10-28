# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Наименование | devops-vm |
| Тип и версия гостевой системы | Linux / Ubuntu (64-bit) |
| Объём оперативной памяти | 2048 МБ |
| Количество ядер процессора | 2 |
| Объём дискового накопителя | 25 ГБ, динамически расширяемый |

## 2. Сетевые интерфейсы

| Параметр | Значение | Адрес |
|---|---|---|
| Сетевой адаптер 1 | NAT | 10.0.2.15 |
| Сетевой адаптер 2 | Виртуальный адаптер хоста (Host-only) | 192.168.56.102 |

## 3. Правило проброса портов

| Параметр | Значение |
|---|---|
| Наименование правила | ssh |
| Протокол | TCP |
| Адрес хостовой системы | 127.0.0.1 |
| Порт хостовой системы | 2222 |
| Адрес гостевой системы | 10.0.2.15 |
| Порт гостевой системы | 22 |

## 4. Учётные записи

| Имя | Принадлежность к группам | Способ аутентификации |
|---|---|---|
| student | sudo | password |
| devops | sudo | ssh, password |

## 5. Служба SSH

- порт - 2222;
- изменённые директивы и их значения:
  PermitRootLogin no
  PasswordAuthentication no
  PubkeyAuthentication yes
  PermitEmptyPasswords no 
  MaxAuthTries 3
  LoginGraceTime 30

  AllowUsers devops

  X11Forwarding no
  ClientAliveInterval 300
  ClientAliveCountMax 2
- расположение файла конфигурации - /etc/ssh/sshd_config.d/99-hardening.conf.


## 6. Правила межсетевого экрана

  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw limit 2222/tcp comment 'SSH rate-limited'
  sudo ufw allow 80/tcp  comment 'HTTP'
  sudo ufw allow 443/tcp comment 'HTTPS'

## 7. Снимки состояния

| Наименование | Момент создания |
|---|---|
| 01-clean-install | Успешная установка VM |
| 02-keys-configured | Первичная настройка SSH |
| 03-ssh-hardened | Усиление защиты SSH |
|  |  |
|  |  |

## 8. Веб-сервер

- устанавливаемый пакет - Nginx; 
- путь к конфигурации ресурса - /etc/nginx/sites-available/devops-site; 
- каталог ресурса - /etc/nginx/, его владелец - учётная запись деплоя devops, права - 755 для каталогов и 644 для файлов; 
- путь к сертификату - /etc/ssl/certs/devops.crt, права - 644;
- путь к ключу - /etc/ssl/private/devops.key, права - 600; 
- команда формирования сертификата:
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```
срок его действия - 365 дней.

## 9. Контейнеризация
- Способ установки Docker Engine - через apt-репозиторий, версия - 29.9.0;
- участники группы docker - пользователь devops; 
- расположение проекта на сервере - /home/devops/app; 
- расположение файла .env - /home/devops/app/.env, его права - 600; 
- публикуемые порты и адреса - 127.0.0.1:5000;
- именованный том - app_db_data; 
- конфигурация обратного прокси-сервера:
```bash
location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```