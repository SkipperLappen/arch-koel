#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
find /tmp/scripts-master/ -type f -name '*.sh' -exec mv -i {} /root/  \;

# pacman packages
####

# define pacman packages
pacman_packages="php npm nodejs composer git mariadb libnotify php-fpm nginx"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aor packages
####

# define arch official repo (aor) packages
aor_packages=""

# define arch official repo (aor) package type e.g. core/community/extra
aor_package_type=""

# call aor script (arch official repo)
source /root/aor.sh

# aur packages
####

# define aur helper
aur_helper="apacman"

# define aur packages
aur_packages=""

# call aur install script (arch user repo)
source /root/aur.sh

# find latest koel release tag from github
release_tag=$(curl -s https://github.com/phanan/koel/releases | grep -P -o -m 1 '(?<=/phanan/koel/releases/tag/)[^"]+')

# git clone koel and install pre-reqs
mkdir -p /opt/koel && cd /opt/koel
git clone --branch "${release_tag}" https://github.com/phanan/koel .
npm install --unsafe-perm
composer install

# copy example koel env file and define
cp ./.env.example ./.env
sed -i 's/ADMIN_EMAIL=/ADMIN_EMAIL=admin@example.com/g' ./.env
sed -i 's/ADMIN_NAME=/ADMIN_NAME=admin/g' ./.env
sed -i 's/ADMIN_PASSWORD=/ADMIN_PASSWORD=admin/g' ./.env
sed -i 's/DB_CONNECTION=/DB_CONNECTION=mysql/g' ./.env
sed -i 's/DB_HOST=/DB_HOST=127.0.0.1/g' ./.env
sed -i 's/DB_DATABASE=/DB_DATABASE=koel/g' ./.env
sed -i 's/DB_USERNAME=/DB_USERNAME=koel-user/g' ./.env
sed -i 's/DB_PASSWORD=/DB_PASSWORD=koel-pass/g' ./.env
sed -i 's/STREAMING_METHOD=.*/STREAMING_METHOD=x-accel-redirect/g' ./.env

# modify php.ini to add in required extension
sed -i 's/;extension=pdo_mysql.so/extension=pdo_mysql.so/g' /etc/php/php.ini
sed -i 's/;extension=exif.so/extension=exif.so/g' /etc/php/php.ini

# configure php-fpm to use tcp/ip connection for listener
echo "" >> /etc/php/php-fpm.conf
echo "; Set php-fpm to use tcp/ip connection" >> /etc/php/php-fpm.conf
echo "listen = 127.0.0.1:7777" >> /etc/php/php-fpm.conf

# configure php-fpm listener for user nobody, group users
echo "" >> /etc/php/php-fpm.conf
echo "; Specify user listener owner" >> /etc/php/php-fpm.conf
echo "listen.owner = nobody" >> /etc/php/php-fpm.conf
echo "" >> /etc/php/php-fpm.conf
echo "; Specify user listener group" >> /etc/php/php-fpm.conf
echo "listen.group = users" >> /etc/php/php-fpm.conf

# container perms
####

# create file with contets of here doc
cat <<'EOF' > /tmp/permissions_heredoc
# set permissions inside container
chown -R "${PUID}":"${PGID}" /opt/koel/ /usr/share/nginx/html/ /etc/nginx/ /etc/php/ /run/php-fpm/ /var/lib/nginx/ /var/log/nginx/ /var/lib/mysql/ /home/nobody
chmod -R 775 /opt/koel/ /usr/share/nginx/html/ /etc/nginx/ /etc/php/ /run/php-fpm/ /var/lib/nginx/ /var/log/nginx/ /var/lib/mysql/ /home/nobody

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /root/init.sh
rm /tmp/permissions_heredoc

# env vars
####

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
