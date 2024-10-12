ARG SRCIMAGE=debian:bookworm-slim

FROM $SRCIMAGE AS builder

ARG LSMB_COMMIT_SHA="ba2f6f4b06e079c3b196c42d57d83d8915bfb2e6"
ARG ARTIFACT_LOCATION="https://github.com/ledgersmb/LedgerSMB/archive/${LSMB_COMMIT_SHA}.tar.gz"

RUN set -x && \
    apt-get update -y && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends apt-file dh-make-perl libmodule-cpanfile-perl git wget curl xz-utils && \
    apt-file update

RUN set -x && \
    wget -O /tmp/ledgersmb.tar.gz "$ARTIFACT_LOCATION" && \
    tar -xzf /tmp/ledgersmb.tar.gz -C /srv && \
    rm /tmp/ledgersmb.tar.gz && \
    mv /srv/LedgerSMB-${LSMB_COMMIT_SHA} /srv/ledgersmb && \
    cd /srv/ledgersmb && \
    cpanfile-dump --with-all-features --recommends --no-configure --no-build --no-test | \
    while read lib; do \
        dh-make-perl locate "$lib" || echo "no : $lib"; \
    done | grep -v dh-make-perl | grep -v 'not found' | grep -vi 'is in Perl ' | cut -d' ' -f4 | sort -u > /srv/derived-deps

FROM $SRCIMAGE AS runtime

LABEL org.opencontainers.image.authors="LedgerSMB project <devel@lists.ledgersmb.org>"
LABEL org.opencontainers.image.title="LedgerSMB double-entry accounting web-application"
LABEL org.opencontainers.image.description="LedgerSMB is a full featured double-entry financial accounting and Enterprise Resource Planning system..."

COPY --from=builder /srv/derived-deps /tmp/derived-deps
COPY --from=builder /srv/ledgersmb /srv/ledgersmb


# Install dependencies
RUN set -x && \
    apt-get update -y && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends \
        procps xz-utils wget curl ca-certificates gnupg iproute2 nginx \
        $(cat /tmp/derived-deps) \
        libclass-c3-xs-perl \
        texlive-plain-generic texlive-latex-recommended texlive-fonts-recommended \
        texlive-xetex fonts-liberation \
        lsb-release gosu && \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    wget -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc > /etc/apt/keyrings/postgresql.asc && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends postgresql-client git cpanminus make gcc libperl-dev vim && \
    rm -rf /var/lib/apt/lists/*


# Install nodejs and yarn
RUN set -x && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g yarn uglify-js@"^2.0"



# LedgerSMB setup
WORKDIR /srv/ledgersmb
RUN cpanm --metacpan --notest \
    --with-feature=starman \
    --with-feature=latex-pdf-ps \
    --with-feature=openoffice \
    --installdeps . && \
    make js

COPY nginx.conf /etc/nginx/nginx.conf

# s6-overlay installation
ARG S6_OVERLAY_VERSION=3.2.0.2

RUN set -ex && \
  ARCH="x86_64" && \
  wget -O /tmp/s6-overlay-noarch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz && \
  wget -O /tmp/s6-overlay-noarch.tar.xz.sha256 https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz.sha256 && \
  wget -O /tmp/s6-overlay-${ARCH}.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz && \
  wget -O /tmp/s6-overlay-${ARCH}.tar.xz.sha256 https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz.sha256 && \
  cd /tmp && \
  sha256sum -c *.sha256 && \
  tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
  tar -C / -Jxpf /tmp/s6-overlay-${ARCH}.tar.xz


COPY start.sh /etc/services.d/ledgersmb/run
RUN chmod +x /etc/services.d/ledgersmb/run && chown www-data:www-data /etc/services.d/ledgersmb/run

COPY services/nginx/run /etc/services.d/nginx/run
RUN chmod +x /etc/services.d/nginx/run && chown www-data:www-data /etc/services.d/nginx/run

RUN chown -R www-data:www-data /etc/services.d

RUN mkdir -p /var/www /srv/ledgersmb/local/conf && \
    chown -R www-data /srv/ledgersmb/local

ENV PERL5LIB=/srv/ledgersmb/lib/:/srv/ledgersmb/old/lib
ENV POSTGRES_HOST ledgersmb-do-user-16410467-0.k.db.ondigitalocean.com
ENV POSTGRES_PORT 25060
ENV DEFAULT_DB defaultdb
ENV UMASK 0002

EXPOSE 8080

USER www-data
ENTRYPOINT ["/init"]

