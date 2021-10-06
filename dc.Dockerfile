FROM docker-hub-remote.dr.corp.adobe.com/node:14.17.6-alpine3.14 AS nodebuilder

COPY . /build
WORKDIR /build

RUN addgroup -S -g 22222 user && \
    adduser -S -u 22222 -g user user

RUN apk --no-cache --virtual build-dependencies add \
  python3
RUN yarn install && \
    yarn kbn bootstrap && \
    yarn build --release --skip-os-packages --skip-docker-centos --skip-docker-ubi

################################################################################
# This Dockerfile was generated from the template at:
#   src/dev/build/tasks/os_packages/docker_generator/templates/Dockerfile
#
# Beginning of multi stage Dockerfile
################################################################################

################################################################################
# Build stage 0 `builder`:
# Extract Kibana artifact
################################################################################
FROM docker-hub-remote.dr.corp.adobe.com/centos:8 AS builder


#RUN cd /opt && \
#  curl --retry 8 -s -L \
#    --output kibana.tar.gz \
#     https://artifacts.elastic.co/downloads/kibana/kibana-7.14.2-linux-$(arch).tar.gz && \
#  cd -


RUN mkdir /usr/share/kibana
WORKDIR /usr/share/kibana
COPY --from=nodebuilder /build/target/kibana-*-linux-x86_64.tar.gz /opt/kibana.tar.gz
RUN tar --strip-components=1 -zxf /opt/kibana.tar.gz
# Ensure that group permissions are the same as user permissions.
# This will help when relying on GID-0 to run Kibana, rather than UID-1000.
# OpenShift does this, for example.
# REF: https://docs.openshift.org/latest/creating_images/guidelines.html
RUN chmod -R g=u /usr/share/kibana

################################################################################
# Build stage 1 (the actual Kibana image):
#
# Copy kibana from stage 0
# Add entrypoint
################################################################################
FROM docker-hub-remote.dr.corp.adobe.com/centos:8
EXPOSE 5601


RUN for iter in {1..10}; do \
      yum update --setopt=tsflags=nodocs -y && \
      yum install --setopt=tsflags=nodocs -y \
        fontconfig freetype shadow-utils nss  && \
      yum clean all && exit_code=0 && break || exit_code=$? && echo "yum error: retry $iter in 10s" && \
      sleep 10; \
    done; \
    (exit $exit_code)

# Add an init process, check the checksum to make sure it's a match
RUN set -e ; \
    TINI_BIN="" ; \
    case "$(arch)" in \
        aarch64) \
            TINI_BIN='tini-arm64' ; \
            ;; \
        x86_64) \
            TINI_BIN='tini-amd64' ; \
            ;; \
        *) echo >&2 "Unsupported architecture $(arch)" ; exit 1 ;; \
    esac ; \
  TINI_VERSION='v0.19.0' ; \
  curl --retry 8 -S -L -O "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/${TINI_BIN}" ; \
  curl --retry 8 -S -L -O "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/${TINI_BIN}.sha256sum" ; \
  sha256sum -c "${TINI_BIN}.sha256sum" ; \
  rm "${TINI_BIN}.sha256sum" ; \
  mv "${TINI_BIN}" /bin/tini ; \
  chmod +x /bin/tini

RUN mkdir /usr/share/fonts/local
RUN curl -L -o /usr/share/fonts/local/NotoSansCJK-Regular.ttc https://github.com/googlefonts/noto-cjk/raw/NotoSansV2.001/NotoSansCJK-Regular.ttc
RUN echo "5dcd1c336cc9344cb77c03a0cd8982ca8a7dc97d620fd6c9c434e02dcb1ceeb3  /usr/share/fonts/local/NotoSansCJK-Regular.ttc" | sha256sum -c -
RUN fc-cache -v

# Bring in Kibana from the initial stage.
COPY --from=builder --chown=22222:0 /usr/share/kibana /usr/share/kibana
WORKDIR /usr/share/kibana
RUN ln -s /usr/share/kibana /opt/kibana

ENV ELASTIC_CONTAINER true
ENV PATH=/usr/share/kibana/bin:$PATH

# Set some Kibana configuration defaults.
COPY --chown=22222:0 config/kibana.yml /usr/share/kibana/config/kibana.yml

# Add the launcher/wrapper script. It knows how to interpret environment
# variables and translate them to Kibana CLI options.
#COPY --chown=1000:0 bin/kibana-docker /usr/local/bin/

# Ensure gid 0 write permissions for OpenShift.
RUN chmod g+ws /usr/share/kibana && \
    find /usr/share/kibana -gid 0 -and -not -perm /g+w -exec chmod g+w {} \;

# Remove the suid bit everywhere to mitigate "Stack Clash"
RUN find / -xdev -perm -4000 -exec chmod u-s {} +

# Provide a non-root user to run the process.
RUN groupadd --gid 22222 kibana && \
    useradd --uid 22222 --gid 22222 -G 0 \
      --home-dir /usr/share/kibana --no-create-home \
      kibana

LABEL org.label-schema.build-date="2021-09-15T09:14:27.489Z" \
  org.label-schema.license="Elastic License" \
  org.label-schema.name="Kibana" \
  org.label-schema.schema-version="1.0" \
  org.label-schema.url="https://www.elastic.co/products/kibana" \
  org.label-schema.usage="https://www.elastic.co/guide/en/kibana/reference/index.html" \
  org.label-schema.vcs-ref="6b971d6410ca4a99271f2abf9d3de68b7a3653a5" \
  org.label-schema.vcs-url="https://github.com/elastic/kibana" \
  org.label-schema.vendor="Elastic" \
  org.label-schema.version="7.14.3" \
  org.opencontainers.image.created="2021-09-15T09:14:27.489Z" \
  org.opencontainers.image.documentation="https://www.elastic.co/guide/en/kibana/reference/index.html" \
  org.opencontainers.image.licenses="Elastic License" \
  org.opencontainers.image.revision="6b971d6410ca4a99271f2abf9d3de68b7a3653a5" \
  org.opencontainers.image.source="https://github.com/elastic/kibana" \
  org.opencontainers.image.title="Kibana" \
  org.opencontainers.image.url="https://www.elastic.co/products/kibana" \
  org.opencontainers.image.vendor="Elastic" \
  org.opencontainers.image.version="7.14.3"


USER kibana

ENTRYPOINT ["/bin/tini", "--"]

CMD ["/usr/local/bin/kibana-docker"]

