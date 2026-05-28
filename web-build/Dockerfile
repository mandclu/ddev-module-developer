ARG BASE_IMAGE
FROM $BASE_IMAGE
USER root

# PHP code quality tools — installed globally via Composer so they
# are independent of the project's own composer.json.
# Tools land in /usr/local/composer/vendor/bin/ and are symlinked
# into /usr/local/bin/ for PATH-transparent access.
ENV COMPOSER_HOME=/usr/local/composer
RUN composer global config allow-plugins.dealerdirect/phpcodesniffer-composer-installer true \
    && composer global require --no-interaction \
      squizlabs/php_codesniffer \
      drupal/coder \
      phpstan/phpstan \
      mglaman/phpstan-drupal \
      phpmd/phpmd \
      palantirnet/drupal-rector \
    && /usr/local/composer/vendor/bin/phpcs \
         --config-set installed_paths \
         /usr/local/composer/vendor/drupal/coder/coder_sniffer \
    && ln -sf /usr/local/composer/vendor/bin/phpcs   /usr/local/bin/phpcs \
    && ln -sf /usr/local/composer/vendor/bin/phpcbf  /usr/local/bin/phpcbf \
    && ln -sf /usr/local/composer/vendor/bin/phpstan /usr/local/bin/phpstan \
    && ln -sf /usr/local/composer/vendor/bin/phpmd   /usr/local/bin/phpmd \
    && ln -sf /usr/local/composer/vendor/bin/rector  /usr/local/bin/rector

# Node.js code quality tools — installed globally via npm.
#
# Versions and packages are aligned with the Drupal GitLab Templates
# package.json (https://www.drupal.org/project/gitlab_templates).
#
# eslint@^8.57.0 — ESLint v8 matches the template; v9 uses a
#   different flat-config format incompatible with Drupal core's
#   .eslintrc.* files.
# eslint-plugin-prettier / eslint-config-prettier / prettier —
#   the template runs Prettier checks inside the eslint job.
# eslint-plugin-yml — the template lints .yml files via ESLint.
# cspell@^8.6.0 — spell-checking job in the template pipeline.
# stylelint-config-standard — base config used by Drupal core and contrib.
RUN npm install -g \
      stylelint \
      stylelint-config-standard \
      eslint@^8.57.0 \
      eslint-config-prettier \
      eslint-plugin-prettier \
      eslint-plugin-yml \
      prettier \
      @babel/eslint-parser \
      @babel/core \
      cspell@^8.6.0
