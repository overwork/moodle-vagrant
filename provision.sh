#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
echo "Running operating system updates..."
apt-get update
apt-get -y upgrade
echo "Installing required packages..."
apt-get -y install \
	apache2 \
	libapache2-mod-php \
	postgresql \
	postgresql-client \
	php-pgsql \
	php-intl \
	php-curl \
	php-xmlrpc \
	php-soap \
	php-gd \
	php-json \
	php-cli \
	php-mcrypt \
	php-pear \
	php-xsl \
	php-zip \
	php-mbstring \
	git
echo "Configuring Apache..."
rm -rf /etc/apache2/sites-enabled
rm -rf /etc/apache2/sites-available
cat <<EOF > /etc/apache2/apache2.conf
Mutex file:\${APACHE_LOCK_DIR} default
PidFile \${APACHE_PID_FILE}
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
User \${APACHE_RUN_USER}
Group \${APACHE_RUN_GROUP}
HostnameLookups Off
ErrorLog \${APACHE_LOG_DIR}/error.log
LogLevel warn
IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf
Include ports.conf
AccessFileName .htaccess
<FilesMatch "^\.ht">
	Require all denied
</FilesMatch>
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent
IncludeOptional conf-enabled/*.conf
<VirtualHost *:80>
	ServerName moodle.local
	DocumentRoot /var/www/moodle/html
	<Directory /var/www/moodle/html>
		Order allow,deny
		Allow from All
	</Directory>
</VirtualHost>
EOF
echo "Creating database..."
PGHBAFILE=$(find /etc/postgresql -name pg_hba.conf | head -n 1)
cat <<EOF > "${PGHBAFILE}"
local   all             postgres                                peer
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    moodle          moodle          127.0.0.1/32            trust
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF
service postgresql restart
sudo -u postgres createuser -SRDU postgres moodle
sudo -u postgres createdb -E UTF-8 -O moodle -U postgres moodle
echo "Creating Moodle directories..."
mkdir -p /var/www/moodle/html
mkdir -p /var/www/moodle/data
cd /var/www/moodle/html
echo "Retrieving latest stable Moodle version..."
git clone https://github.com/moodle/moodle.git .
LATEST_VERSION=$(git tag | awk '{print $1}' | grep -v '}$' | grep -v 'beta' | grep -v 'rc' | sed 's/^v//' | sort -t. -k 1,1n -k 2,2n -k 3,3n | tail -n1)
echo "Checking out Moodle version ${LATEST_VERSION}..."
git checkout "tags/v${LATEST_VERSION}" -b "v${LATEST_VERSION}"
echo "Installing Moodle..."
php admin/cli/install.php \
	--lang="en" \
	--wwwroot="http://moodle.local" \
	--dataroot="/var/www/moodle/data" \
	--dbtype="pgsql" \
	--dbname="moodle" \
	--dbuser="moodle" \
	--fullname="Moodle" \
	--shortname="moodle" \
	--adminpass="Admin1!" \
	--agree-license \
	--non-interactive
chown www-data:www-data -R /var/www/moodle

echo "Setting up PHPUnit..."
wget https://phar.phpunit.de/phpunit.phar
chmod +x phpunit.phar
sudo mv phpunit.phar /usr/local/bin/phpunit
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('SHA384', 'composer-setup.php') === 'e115a8dc7871f15d853148a7fbac7da27d6c0030b848d9b3dc09e2a0388afed865e6a3d6b3c0fad45c48e2b5fc1196ae') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
sudo php composer-setup.php
php -r "unlink('composer-setup.php');"
php composer.phar install

echo "Restarting Apache..."
service apache2 restart
cat <<EOF
Service installed at http://moodle.local/

You will need to add a hosts file entry for:

moodle.local points to 192.168.33.10

username: admin
password: Admin1!

EOF
cat <<EOF > /etc/cron.d/moodle
* * * * * www-data /usr/bin/env php /var/www/moodle/html/admin/cli/cron.php
EOF
