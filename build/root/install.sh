#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# pacman packages
####

# define pacman packages
pacman_packages="php npm nodejs composer git mariadb libnotify php-fpm nginx expect yarn pngquant"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages=""

# call aur install script (arch user repo)
source aur.sh

# github releases
####

# download koel
github.sh -df "github-download.zip" -dp "/tmp" -ep "/tmp/extracted" -ip "/opt/koel" -go "phanan" -gr "koel" -rt "source" -grs "v4.2.2"

# install koel
cd /opt/koel && yarn install --unsafe-perm
composer install

# another hack, laravel 5.4 uses the utf8mb4 character set by default, which includes support for storing "emojis" in the database.
# mysql 5.7.7+ / mariadb 10.2.2+) both have this new character set by default, so this is only a tempory hack until they are updated.
sed -i -e 's~mb4~~g' /opt/koel/config/database.php

# config
####

# copy example koel env file and define
cp /home/nobody/koel/.env.example /opt/koel/.env.backup || ls -al
sed -i 's/ADMIN_EMAIL=/ADMIN_EMAIL=admin@example.com/g' /opt/koel/.env.backup
sed -i 's/ADMIN_NAME=/ADMIN_NAME=admin/g' /opt/koel/.env.backup
sed -i 's/ADMIN_PASSWORD=/ADMIN_PASSWORD=admin/g' /opt/koel/.env.backup
sed -i 's/DB_CONNECTION=/DB_CONNECTION=mysql/g' /opt/koel/.env.backup
sed -i 's/DB_HOST=/DB_HOST=127.0.0.1/g' /opt/koel/.env.backup
sed -i 's/DB_DATABASE=/DB_DATABASE=koel/g' /opt/koel/.env.backup
sed -i 's/DB_USERNAME=/DB_USERNAME=koel-user/g' /opt/koel/.env.backup
sed -i 's/DB_PASSWORD=/DB_PASSWORD=koel-pass/g' /opt/koel/.env.backup
sed -i 's/STREAMING_METHOD=.*/STREAMING_METHOD=x-accel-redirect/g' /opt/koel/.env.backup
sed -i 's/APP_MAX_SCAN_TIME=.*/APP_MAX_SCAN_TIME=6000/g' /opt/koel/.env.backup

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

# create socket for mysqld
mkdir -p /run/mysqld

# container perms
####

# define comma separated list of paths 
install_paths="/opt/koel,/usr/share/nginx/html,/etc/nginx,/etc/php,/run/php-fpm,/var/lib/nginx,/var/log/nginx,/var/lib/mysql,/home/nobody"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different 
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/local/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

# cleanup
cleanup.sh
