FROM debian:latest
MAINTAINER Alex Sol <mal6lsh@gmail.com>

VOLUME /var/spool/postfix

ARG DomainName
ARG UserName
ARG UserPass

RUN echo mail > /etc/hostname
RUN echo "127.0.0.1 localhost mail mail.${DomainName}" > /etc/hosts \
 && chown root:root /etc/hosts

# Установка postfix в автоматичеком режиме,
# без диалоговых окон, автоматический выбор параметров во время установки
# Так же установка dovecot + opendkim
RUN echo "postfix postfix/main_mailer_type string Internet site" > postfix_silent_install.txt \
 && echo "postfix postfix/mailname string mail.${DomainName}" >> postfix_silent_install.txt \
 && debconf-set-selections postfix_silent_install.txt
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
 postfix \
 opendkim \
 opendkim-tools \
 rsyslog

# Dkim + ключи подписи + какую почту подписывать
RUN mkdir /etc/opendkim/ \
 && opendkim-genkey -D /etc/opendkim/ -d $(hostname -d) -s $(hostname) \
 && chgrp opendkim /etc/opendkim/* \
 && chmod g+r /etc/opendkim/* \
 && gpasswd -a postfix opendkim
# && SOCKET="local:/var/run/opendkim/opendkim.sock"  \
# && SOCKET="inet:12301@localhost"
ADD opendkim.conf /etc/opendkim.conf
RUN echo $(hostname -f | sed s/\\./._domainkey./) $(hostname -d):$(hostname):$(ls /etc/opendkim/*.private) | tee -a /etc/opendkim/keytable \
 && echo $(hostname -d) $(hostname -f | sed s/\\./._domainkey./) | tee -a /etc/opendkim/signingtable

# Создаем пользователя с его паролем и группы
RUN useradd -m -d /home/${UserName} -p ${UserPass} -s /bin/false ${UserName} \
 && echo "root: ${UserName}" >> /etc/aliases \
 && newaliases

# Настройка Postfix, подгружаем файл настройки с уже настроенного рабочего клиента
# Настройка Postfix отпрвлять письма на подпись в DKIM
ADD main.cf /etc/postfix/main.cf
RUN postconf -e "myhostname = mail.${DomainName}" \
 && postconf -e "mydestination = mail.${DomainName}, ${DomainName}, localhost.localdomain, localhost" \
 && postconf -e milter_default_action=accept \
 && postconf -e milter_protocol=2 \
 && postconf -e smtpd_milters=unix:/var/run/opendkim/opendkim.sock \
 && postconf -e non_smtpd_milters=unix:/var/run/opendkim/opendkim.sock

RUN service postfix stop ; service opendkim stop
EXPOSE 25 143 110

# стартуем postfix и логирование
CMD ["sh", "-c", "service postfix start ; service opendkim start ; service rsyslog start ; tail -f /dev/null"]
