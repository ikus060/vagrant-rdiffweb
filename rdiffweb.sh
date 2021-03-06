#!/bin/bash
# Copyright (C) 2015 Patrik Dufresne Service Logiciel inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#shopt -o -s xtrace

# Variables
RDIFFWEB_VERSION="master"
# Locations
RDIFFWEB_URL="https://github.com/ikus060/rdiffweb/archive/$RDIFFWEB_VERSION.tar.gz"
#RDIFFWEB_URL="http://git.patrikdufresne.com/pdsl/rdiffweb/repository/archive.tar.gz?ref=$RDIFFWEB_VERSION"
# Constant
INSTALL_LOG="/tmp/rdiffweb-install.log"

# Typography
ESC_SEQ="\x1b["
BOLD=`tput bold`
NORM=`tput sgr0`
COL_RESET=$ESC_SEQ"39;49;00m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_RED=$ESC_SEQ"31;01m"
STATUS_FAIL="[$COL_RED${BOLD}FAIL${NORM}$COL_RESET]"
STATUS_OK="[$COL_GREEN${BOLD} OK ${NORM}$COL_RESET]"

declare -rx PROGNAME=${0##*/}
declare -rx PROGPATH=$(readlink -e "${0%/*}")/

function dependencies_install() {
  # Fix apt key
  apt-get update
  apt-get install debian-keyring debian-archive-keyring
  apt-key update

  # Install dependencies
  apt-get update
  apt-get install --force-yes -y python-cherrypy3 \
      python-pysqlite2 \
      libsqlite3-dev \
      python-jinja2 \
      python-setuptools \
      python-babel \
      rdiff-backup
  apt-get clean
  return 0
}

function rdiffweb_install() {
  # Remote previous config
  if [ -e "/etc/rdiffweb/rdw.conf" ]; then
    rm -Rf "/etc/rdiffweb/rdw.conf"
  fi
  if [ -e "/etc/rdiffweb/rdw.db" ]; then
    rm -Rf "/etc/rdiffweb/rdw.db"
  fi
  # Download rdiffweb
  wget --no-check-certificate -O rdiffweb.tar.gz "$RDIFFWEB_URL"
  # Extract
  tar zxf rdiffweb.tar.gz
  # Compile and install
  cd rdiffweb*
  python setup.py build
  [ "$?" -eq "0" ] || return 1
  python setup.py install
  [ "$?" -eq "0" ] || return 1

  # Since 0.8.1, init script and confif are not deployed automatically.
  if [ ! -e "/etc/init.d/rdiffweb" ]; then
    cp extras/init/rdiffweb /etc/init.d/rdiffweb
    chmod +x /etc/init.d/rdiffweb
  fi
  mkdir -p /etc/rdiffweb/
  if [ ! -e "/etc/rdiffweb/rdw.conf" ]; then
    cp rdw.conf /etc/rdiffweb/rdw.conf
  fi

  # Add rdiffweb to startup
  update-rc.d rdiffweb defaults

  # Start rdiffweb
  /etc/init.d/rdiffweb start
  [ "$?" -eq "0" ] || return 1

  # Wait 2 sec.
  sleep 2

  curl --location http://localhost:8080 > /dev/null
  [ "$?" -eq "0" ] || return 1

  return 0
}

function data_install() {
  # Search testcases.tar.gz
  TESTCASES=""
  [ -e "${PROGPATH}testcases.tar.gz" ] && TESTCASES="${PROGPATH}testcases.tar.gz"
  [ -e "/vagrant/testcases.tar.gz" ] && TESTCASES="/vagrant/testcases.tar.gz"
  if [ -z "$TESTCASES" ]; then 
    echo "testcases.tar.gz not found"
    return 1
  fi
  [ -e "$TESTCASES" ] || return 1

  # Create default /backups directory
  mkdir -p "/backups"
  cd "/backups"
  tar -zxvf "$TESTCASES"

  # Refresh the repository list using `curl`
  export COOKIE="/tmp/$$.cjar"
  curl --cookie "$COOKIE" --cookie-jar "$COOKIE" \
      --data "login=admin" --data "password=admin123" --location "http://localhost:8080/login/" > /dev/null
  curl --cookie "$COOKIE" --cookie-jar "$COOKIE" \
      --data "action=update_repos" --location "http://localhost:8080/prefs/#" > /dev/null
  [ -e "$COOKIE" ] && rm "$COOKIE"
}

# Main process execute each step
dependencies_install > ${INSTALL_LOG} 2>&1
if [[ $? -ne 0 ]];
  then
    echo -e "${BOLD}Step1${NORM}  => Install dependencies                                  ${STATUS_FAIL}"
  else
    echo -e "${BOLD}Step1${NORM}  => Install dependencies                                  ${STATUS_OK}"
fi

# Install rdiffweb
rdiffweb_install >> ${INSTALL_LOG} 2>&1
if [[ $? -ne 0 ]];
  then
    echo -e "${BOLD}Step2${NORM}  => Install rdiffweb                                      ${STATUS_FAIL}"
  else
    echo -e "${BOLD}Step2${NORM}  => Install rdiffweb                                      ${STATUS_OK}"
fi

# Create default data
data_install >> ${INSTALL_LOG} 2>&1
if [[ $? -ne 0 ]];
  then
    echo -e "${BOLD}Step2${NORM}  => Add repository                                        ${STATUS_FAIL}"
  else
    echo -e "${BOLD}Step2${NORM}  => Add repository                                        ${STATUS_OK}"
fi

