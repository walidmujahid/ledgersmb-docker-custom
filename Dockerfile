# Build time variables

ARG SRCIMAGE=debian:bookworm-slim


FROM $SRCIMAGE AS builder

ARG LSMB_COMMIT_SHA="0bcd8092e932be760a27fcbce038ce494462fc7a"
ARG ARTIFACT_LOCATION="https://github.com/ledgersmb/LedgerSMB/archive/${LSMB_COMMIT_SHA}.tar.gz"

RUN set -x ; \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y dist-upgrade && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install dh-make-perl libmodule-cpanfile-perl git wget curl && \
  apt-file update

RUN set -x ; \
  wget --quiet -O /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz "$ARTIFACT_LOCATION" && \
  tar -xzf /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz --directory /srv && \
  rm -f /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz && \
  mv /srv/LedgerSMB-${LSMB_COMMIT_SHA} /srv/ledgersmb && \
  cd /srv/ledgersmb && \
  ( ( for lib in $( cpanfile-dump --with-all-features --recommends --no-configure --no-build --no-test ) ; \
    do \
      if dh-make-perl locate "$lib" 2>/dev/null ; \
      then  \
        : \
      else \
        echo no : $lib ; \
      fi ; \
    done ) | grep -v dh-make-perl | grep -v 'not found' | grep -vi 'is in Perl ' | cut -d' ' -f4 | sort | uniq | tee /srv/derived-deps ) && \
  cat /srv/derived-deps


#
#
#  The real image build starts here
#
#


FROM  $SRCIMAGE
LABEL org.opencontainers.image.authors="LedgerSMB project <devel@lists.ledgersmb.org>"
LABEL org.opencontainers.image.title="LedgerSMB double-entry accounting web-application"
LABEL org.opencontainers.image.description="LedgerSMB is a full featured double-entry financial accounting and Enterprise\
 Resource Planning system accessed via a web browser (Perl/JS with a PostgreSQL\
 backend) which offers 'Accounts Receivable', 'Accounts Payable' and 'General\
 Ledger' tracking as well as inventory control and fixed assets handling. The\
 LedgerSMB client can be a web browser or a programmed API call. The goal of\
 the LedgerSMB project is to bring high quality ERP and accounting capabilities\
 to Small and Midsize Businesses."

ARG LSMB_COMMIT_SHA="0bcd8092e932be760a27fcbce038ce494462fc7a"
ARG ARTIFACT_LOCATION="https://github.com/ledgersmb/LedgerSMB/archive/${LSMB_COMMIT_SHA}.tar.gz"

# Install Perl, Tex, Starman, psql client, and all dependencies
# Without libclass-c3-xs-perl, performance is terribly slow...

# Installing psql client directly from instructions at https://wiki.postgresql.org/wiki/Apt
# That mitigates issues where the PG instance is running a newer version than this container


COPY --from=builder /srv/derived-deps /tmp/derived-deps

RUN set -x ; \
  echo -n "APT::Install-Recommends \"0\";\nAPT::Install-Suggests \"0\";\n" >> /etc/apt/apt.conf && \
  mkdir -p /usr/share/man/man1/ && \
  mkdir -p /usr/share/man/man2/ && \
  mkdir -p /usr/share/man/man3/ && \
  mkdir -p /usr/share/man/man4/ && \
  mkdir -p /usr/share/man/man5/ && \
  mkdir -p /usr/share/man/man6/ && \
  mkdir -p /usr/share/man/man7/ && \
  mkdir -p /usr/share/man/man8/ && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y dist-upgrade && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install \
    wget curl ca-certificates gnupg iproute2 nginx \
    $( cat /tmp/derived-deps ) \
    libclass-c3-xs-perl \
    texlive-plain-generic texlive-latex-recommended texlive-fonts-recommended \
    texlive-xetex fonts-liberation \
    lsb-release && \
  echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc > /etc/apt/keyrings/postgresql.asc && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install postgresql-client && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install git cpanminus make gcc libperl-dev && \
  wget --quiet -O /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz "$ARTIFACT_LOCATION" && \
  tar -xzf /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz --directory /srv && \
  rm -f /tmp/ledgersmb-${LSMB_COMMIT_SHA}.tar.gz && \
  mv /srv/LedgerSMB-${LSMB_COMMIT_SHA} /srv/ledgersmb && \
  cd /srv/ledgersmb && \
  cpanm --metacpan --notest \
    --with-feature=starman \
    --with-feature=latex-pdf-ps \
    --with-feature=openoffice \
    --installdeps /srv/ledgersmb/ 

RUN set -x ; \
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -  && \
  apt-get -y install nodejs && \
  npm install -g yarn && \
  npm install -g uglify-js@">=2.0 <3.0" && \
  rm -rf ~/.cpanm/ /var/lib/apt/lists/* /usr/share/man/*

WORKDIR /srv/ledgersmb

RUN make js

# master requirements

# Configure outgoing mail to use host, other run time variable defaults

## MAIL
# '__CONTAINER_GATEWAY__' is a magic value which will be substituted
# with the actual gateway IP address
ENV LSMB_MAIL_SMTPHOST __CONTAINER_GATEWAY__
#ENV LSMB_MAIL_SMTPPORT 25
#ENV LSMB_MAIL_SMTPSENDER_HOSTNAME (container hostname)
#ENV LSMB_MAIL_SMTPTLS
#ENV LSMB_MAIL_SMTPUSER
#ENV LSMB_MAIL_SMTPPASS
#ENV LSMB_MAIL_SMTPAUTHMECH

## DATABASE
ENV POSTGRES_HOST ledgersmb-do-user-16410467-0.k.db.ondigitalocean.com
ENV POSTGRES_PORT 25060
ENV DEFAULT_DB defaultdb

COPY start.sh /usr/local/bin/start.sh
COPY nginx.conf /etc/nginx/nginx.conf

RUN chmod +x /usr/local/bin/start.sh && \
  mkdir -p /var/www && \
  mkdir -p /srv/ledgersmb/local/conf && \
  chown -R www-data /srv/ledgersmb/local

# Create Nginx temporary directories and set permissions
RUN mkdir -p /tmp/client_body /tmp/proxy_temp /tmp/fastcgi_temp /tmp/scgi_temp /tmp/uwsgi_temp && \
    chown -R www-data:www-data /tmp/*

# Work around an aufs bug related to directory permissions:
RUN mkdir -p /tmp && chmod 1777 /tmp

# Internal Port Expose
EXPOSE 8080

USER www-data
CMD ["start.sh"]
