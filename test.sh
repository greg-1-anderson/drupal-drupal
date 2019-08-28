#!/bin/bash

WORK_DIR="${1:-/tmp}"

# If running on Mac, it is necessary to install gnu sed via:
#   brew install gnu-sed
if [ -f "/usr/local/opt/gnu-sed/libexec/gnubin/sed" ] ; then
  PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
fi

# Clean up some work directories
rm -rf $WORK_DIR/drupal-drupal-composer
rm -rf $WORK_DIR/drupal-untarred
rm -rf $WORK_DIR/package-metadata


# Set up our own packages.json metadata project
mkdir $WORK_DIR/package-metadata
cp composer.json composer.lock $WORK_DIR/package-metadata
git -C $WORK_DIR/package-metadata init
git -C $WORK_DIR/package-metadata add -A .
git -C $WORK_DIR/package-metadata commit -m 'Initial commit'
echo "{ \"package\": { \"name\": \"greg-1-anderson/drupal-drupal-composer\", \"version\": \"1.0.0\", \"source\": { \"url\": \"$WORK_DIR/package-metadata/.git\", \"type\": \"git\", \"reference\": \"master\" } } }" > $WORK_DIR/packages.json

# Use 'composer create-project' to create our SUT
composer create-project -n --repository-url=$WORK_DIR/packages.json greg-1-anderson/drupal-drupal-composer $WORK_DIR/drupal-drupal-composer
composer -n --working-dir=$WORK_DIR/drupal-drupal-composer composer:scaffold

# Look up the version of drupal/core in our SUT, and use it to download a tarball
DRUPAL_CORE_VERSION=$(composer --working-dir=$WORK_DIR/drupal-drupal-composer show drupal/core | grep 'versions' | grep -o -E '\*\ .+' | cut -d' ' -f2 | cut -d',' -f1;)
echo "Drupal core version is $DRUPAL_CORE_VERSION"
curl -o $WORK_DIR/drupal.tgz https://ftp.drupal.org/files/projects/drupal-$DRUPAL_CORE_VERSION.tar.gz
ls $WORK_DIR
cd $WORK_DIR
tar -xzvf drupal.tgz >/dev/null 2>&1
mv drupal-$DRUPAL_CORE_VERSION drupal-untarred

# Repair the tarball:
#  - Remove info from drupal.org packaging from info.yml files
#  - Remove the "composer" directory that contains things like Composer plugins
#    and template projects that are either not included, or installed into the
#    vendor directory on Composer-managed sites.
#  - Remove the 'test' directory in mikey179/vfsstream which Vendor Hardening removes, but the tarball does not
find $WORK_DIR/drupal-untarred -name "*.info.yml" -exec sed -e 's/^# version:/version:/' -e 's/^# core:/core:/' -e '/# Information added by Drupal.org packaging script/,$d' -i {} \;
rm -rf $WORK_DIR/drupal-untarred/composer
rm -rf $WORK_DIR/drupal-untarred/vendor/mikey179/vfsstream/src/test

# Extra files that exist in the SUT that are not present in the tarball.
# These files are excluded from export in the .gitattributes file.
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/CONTRIBUTING.md
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/.gitattributes
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/.gitignore
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/phpdoc.ini.dist
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/phpunit.xml.dist
rm -rf $WORK_DIR/drupal-drupal-composer/vendor/behat/mink/.travis.yml

set -ex

# Check for differences between the tarball and the SUT (except vendor)
#
# Explanation of files from exception list:
#
#     - .git:         Git metadata that we should never compare
#     - autoload.php: Generated file that is known to be different than legacy version
#     - LICENSE.txt:  Placed by packaging script (should we scaffold this?)
#     - vendor:       Ignored because we diff it separately below
#
# Files that we expect to be different because the project sources are different:
#
#     - .gitignore
#     - composer.json
#     - composer.lock
#
diff -rBq \
  -x .git \
  -x .gitignore \
  -x composer.json \
  -x composer.lock \
  -x autoload.php \
  -x LICENSE.txt \
  -x vendor \
  $WORK_DIR/drupal-untarred $WORK_DIR/drupal-drupal-composer

# Check for differences between the vendor directory in the tarball and the SUT
#
# Explanation of files from exception list:
#
#     - .git:          Git metadata that we should never compare
#     - .htaccess:     Written by vendor hardening plugin
#     - web.config:    Also written by vendor hardening plugin
#     - autoload.php:  Generated by Composer
#     - composer:      Contains files generated by Composer
#     - drupalcs.info: In vendor/drupal/coder; contains info written by packaging script
#
#     - mink-selenium2-driver: Installed as 'dev-master', so might see small differences
#     - greg-1-anderson: Temporary, holds forked projects.
#
# We also skip the core-file-security, core-composer-scaffold and
# core-vendor-hardening, which exist in the vendor directory of our
# Composer-generated site, but are in the 'composer' directory (at the project
# root) in the tarball.
diff -rBq \
  -x .git \
  -x .htaccess \
  -x web.config \
  -x autoload.php \
  -x composer \
  -x drupalcs.info \
  -x core-file-security \
  -x core-composer-scaffold \
  -x core-vendor-hardening \
  -x mink-selenium2-driver \
  -x greg-1-anderson \
  $WORK_DIR/drupal-untarred/vendor $WORK_DIR/drupal-drupal-composer/vendor
