#!/bin/bash

LIBS="libpng libkrb5 libmysqlclient libpcre"
# usage - ./build_php.sh php52
# where php52 is a PHP source directory

# current directory
DIR="$( cd "$( dirname "$0" )" && pwd )"
TMPDIR=$(mktemp -d /tmp/php52Setup.XXXX)

# requires a php source directory as a first argument
#if [ ! -d "$1" ]
#then
#    echo "Php source is not a valid directory"
#    exit 1
#fi

# hard code /usr/local/php52 as our app depends on this location

die() { echo $* 1>&2 ; exit 1 ; }

#apt-get update && apt-get upgrade -y
# Core dependancies
basicbuildpkgs () {
apt-get install \
apache2 \
gcc \
g++ \
perl \
make \
automake \
autoconf \
subversion \
git \
apache2-prefork-dev \
libxml2-dev \
pkg-config \
libbz2-dev \
libcurl4-openssl-dev \
libjpeg8-dev \
libpng12-dev \
libpng3 libc-client2007e-dev \
libmcrypt-dev \
libncurses-dev \
libreadline-dev \
libxslt1-dev \
libltdl-dev \
rabbitmq-server \
apache2-mpm-prefork \
links \
re2c \
libmagic-dev \
libapache2-mod-fast***REMOVED***i \
ntp \
libevent-core-2.0-5 \
libevent-2.0-5 \
libfreetype6-dev \
patch \
memcached -y
}

basicbuildpkgs
#exit 0

# Download php, suhosin patch and SSL patch
echo "Downloading files..."
cp php-5.2.17.tar.gz $TMPDIR
cd "$TMPDIR"
#wget http://museum.php.net/php5/php-5.2.17.tar.gz || die "Failed to find / download php 5.2"
tar -xzf php-5.2.17.tar.gz
wget http://download.suhosin.org/suhosin-patch-5.2.16-0.9.7.patch.gz || die "Failed to find / download suhosin patch"
gunzip suhosin-patch-5.2.16-0.9.7.patch.gz
cd php-5.2.17
patch -p 1 -i ../suhosin-patch-5.2.16-0.9.7.patch
cd ..
wget "https://bugs.php.net/patch-display.php?bug_id=54736&patch=debian_patches_disable_SSLv2_for_openssl_1_0_0.patch&revision=1305414559&download=1" -O debian_patches_disable_SSLv2_for_openssl_1_0_0.patch || die "Failed to find / download debian ssl v2 disable patch."
cd php-5.2.17
patch -p 1 -i ../debian_patches_disable_SSLv2_for_openssl_1_0_0.patch
cd ..
wget "http://php-fpm.org/downloads/php-5.2.17-fpm-0.5.14.diff.gz" || die "Failed to download fpm patch"
gunzip php-5.2.17-fpm-0.5.14.diff.gz
cd php-5.2.17
patch -p 1 -i ../php-5.2.17-fpm-0.5.14.diff


# symlink libs, 5.2. doesn't know about multiarch paths
echo "Symlink libraries for multiarch"
for lib in $LIBS; do
  if [ ! -f "/usr/lib/$lib.so" ]; then
    if [ -f "/usr/lib/x86_64-linux-gnu/$lib.so" ]; then
      ln -s "/usr/lib/x86_64-linux-gnu/$lib.so" "/usr/lib/$lib.so"
    fi
  fi
done



# define full path to php sources
#SRC="$DIR/$1"
SRC="/usr/local/php52"
mkdir "$SRC"

# # Here follows paths for installation binaries and general settings
# PREFIX="$SRC" # will install binaries in ~/php/bin directory, make sure it is exported in your $PATH for executables
# SBIN_DIR="$SRC" # all binaries will go to ~/php/bin
# CONF_DIR="$SRC" # will use php.ini located here as ~/php/php.ini
# CONFD_DIR="$SRC/conf.d" # will load all extra configuration files from ~/php/conf.d directory
# MAN_DIR="$SRC/share/man" # man pages goes here

# EXTENSION_DIR="$SRC/share/modules" # all shared modules will be installed in ~/php/share/modules phpize binary will configure it accordingly
# export EXTENSION_DIR
# PEAR_INSTALLDIR="$SRC/share/pear" # pear package directory
# export PEAR_INSTALLDIR

# if [ ! -d "$CONFD_DIR" ]; then
#     mkdir -p $CONFD_DIR
# fi

# here follows a main configuration script
# PHP_CONF="--prefix=$PREFIX \
# --sbindir=$SBIN_DIR \
# --sysconfdir=$CONF_DIR \
# --localstatedir=/var \
# --with-layout=GNU \
# --with-config-file-path=$CONF_DIR \
# --with-config-file-scan-dir=$CONFD_DIR \
# --disable-rpath \
# --mandir=$MAN_DIR \
# "

# build configure, not included in git versions
#if [ ! -f "$SRC/configure" ]; then
#    ./buildconf --force
#fi

# Additionally you can add these, if they are needed:
#   --enable-ftp
#   --enable-exif
#   --enable-calendar
#   --with-snmp=/usr
#   --with-pspell
#   --with-tidy=/usr
#   --with-xmlrpc
#   --with-xsl=/usr
# and any other, run "./configure --help" inside php sources

# define extension configuration
#EXT_CONF="--with-apxs2=/usr/bin/apxs2 \
EXT_CONF="--with-config-file-path=/usr/local/php52/etc \
    --with-bz2 \
    --with-curl \
    --with-gd \
    --with-freetype-dir \
    --with-gettext \
    --with-imap \
    --with-imap-ssl \
    --with-kerberos \
    --with-mcrypt \
    --with-mime-magic \
    --with-mysql \
    --with-mysqli \
    --with-ncurses \
    --with-openssl \
    --with-pear \
    --with-pdo-mysql \
    --with-readline \
    --with-xsl \
    --with-zlib-dir \
    --prefix=/usr/local/php52 \
    --enable-fast***REMOVED***i
    --enable-fpm
    --enable-bcmath \
    --enable-calendar \
    --enable-dba \
    --enable-dbase \
    --enable-exif \
    --enable-fileinfo \
    --enable-ftp \
    --enable-mbstring \
    --enable-pcntl \
    --enable-shmop \
    --enable-soap \
    --enable-sockets \
    --enable-sysvmsg \
    --enable-sysvsem \
    --enable-sysvshm \
    --enable-wddx \
    --enable-zip \
"

# adapt fpm user and group if different wanted
#PHP_FPM_CONF="--enable-fpm \
#    --with-fpm-user=www-data \
#    --with-fpm-group=www-data
#"

# CLI, php-fpm and apache2 module
./configure $EXT_CONF

# CGI and FastCGI
#./configure $PHP_CONF --disable-cli --enable-***REMOVED***i $EXT_CONF

# build sources
make
checkinstall make install
# cleanup
rm -rf "TMPDIR"

# Grab php.ini from /home/***REMOVED***/prod/php.ini (in future grab from svn)
#cp /home/***REMOVED***/prod/php.ini /usr/local/php52/etc/php.ini
# grab ***REMOVED*** folder from web1/2 and all apache vhost files
# replace values, edit hosts file.....
# add self-signed cert or remove ssl parts
