FROM adoptopenjdk/openjdk11:alpine

ENV ES_SUDACHI_VERSION=v2.1.0
ENV ELASTICSEARCH_VERSION=7.13.3

RUN apk add --no-cache git && \
    git clone https://github.com/WorksApplications/elasticsearch-sudachi.git -b ${ES_SUDACHI_VERSION} --depth 1 && \
    cd elasticsearch-sudachi && \
    ./gradlew -PelasticsearchVersion=${ELASTICSEARCH_VERSION} build

FROM adoptopenjdk/openjdk11:alpine

ENV ES_VERSION 7.13.3
ENV YQ_VERSION 2.4.1

ENV DOWNLOAD_URL "https://artifacts.elastic.co/downloads/elasticsearch"
ENV ES_TARBAL "${DOWNLOAD_URL}/elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz"
ENV ES_TARBALL_ASC "${DOWNLOAD_URL}/elasticsearch-${ES_VERSION}-linux-x86_64.tar.gz.asc"
ENV GPG_KEY "46095ACC8548582C1A2699A9D27D666CD88E42B4"

# Install necessary tools
RUN apk add --no-cache --update bash ca-certificates su-exec util-linux curl runit

# Install Elasticsearch.
RUN apk add --no-cache -t .build-deps gnupg openssl \
  && cd /tmp \
  && echo "===> Install Elasticsearch..." \
  && curl -o elasticsearch.tar.gz -Lskj "$ES_TARBAL"; \
	if [ "$ES_TARBALL_ASC" ]; then \
		curl -o elasticsearch.tar.gz.asc -Lskj "$ES_TARBALL_ASC"; \
		export GNUPGHOME="$(mktemp -d)"; \
		gpg --keyserver keyserver.ubuntu.com --recv-keys "$GPG_KEY"; \
		gpg --batch --verify elasticsearch.tar.gz.asc elasticsearch.tar.gz; \
    [ $? -eq 0 ] || exit 1; \
		rm -r "$GNUPGHOME" elasticsearch.tar.gz.asc; \
	fi; \
  tar -xf elasticsearch.tar.gz \
  && ls -lah \
  && mv elasticsearch-$ES_VERSION /elasticsearch \
  && adduser -DH -s /sbin/nologin elasticsearch \
  && mkdir -p /elasticsearch/config/scripts /elasticsearch/plugins \
  && chown -R elasticsearch:elasticsearch /elasticsearch \
  && rm -rf /elasticsearch/jdk /elasticsearch/logs \
  && ln -s /data/data /elasticsearch/data \
  && ln -s /data/log /elasticsearch/logs \
  && rm -rf /tmp/* \
  && apk del --purge .build-deps

# Add Elasticsearch to PATH
ENV PATH /elasticsearch/bin:$PATH

# Set default working directory to /elasticsearch
WORKDIR /elasticsearch

# Set environment variables defaults
ENV NODE_NAME="" \
    ES_TMPDIR="/elasticsearch/tmp" \
    ES_JAVA_OPTS="-Xms512m -Xmx512m" \
    ES_JAVA_HOME="$JAVA_HOME" \
    CLUSTER_NAME="elasticsearch" \
    NODE_MASTER=true \
    NODE_DATA=true \
    NODE_INGEST=true \
    HTTP_CORS_ENABLE=true \
    HTTP_CORS_ALLOW_ORIGIN=* \
    DISCOVERY_SERVICE="" \
    INITIAL_MASTER_NODES="" \
    SSL_ENABLE=false \
    MODE="" \
    NETWORK_HOST=_site_ \
    HTTP_CORS_ENABLE=true \
    MAX_LOCAL_STORAGE_NODES=1 \
    SHARD_ALLOCATION_AWARENESS="" \
    SHARD_ALLOCATION_AWARENESS_ATTR="" \
    MEMORY_LOCK=true \
    REPO_LOCATIONS="" \
    KEY_PASS=""

COPY --from=0 /elasticsearch-sudachi/build/distributions/analysis-sudachi-7.13.3-2.1.0.zip /
# Fix Docker Hub Automated Build cannot check java binary execute permission
RUN sed -i -e 's/ -x / -f /' /elasticsearch/bin/elasticsearch-env && \
    elasticsearch-plugin install --batch ingest-attachment && \
    elasticsearch-plugin install --batch analysis-icu && \
    elasticsearch-plugin install --batch analysis-kuromoji && \
    elasticsearch-plugin install --batch repository-s3 && \
    elasticsearch-plugin install --batch file:///analysis-sudachi-7.13.3-2.1.0.zip && \
    rm -f /analysis-sudachi-7.13.3-2.1.0.zip && \
    curl -o sudachi-dictionary.zip -Lskj http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict/sudachi-dictionary-20210608-core.zip && \
    unzip -d /elasticsearch/config/sudachi -j sudachi-dictionary.zip && \
    rm -f sudachi-dictionary.zip && \
    sed -i -e 's/ -f / -x /' /elasticsearch/bin/elasticsearch-env

# Add Elasticsearch configuration files
ADD config /elasticsearch/config

# run.sh run Elasticsearch after changing ownership and some configuration
COPY run.sh /
RUN mkdir /etc/service/elasticsearch
RUN ln -s /run.sh /etc/service/elasticsearch/run

# /elasticsearch/config/certs directory is used to mount SSL certificates
RUN mkdir /elasticsearch/config/certs
RUN chown elasticsearch:elasticsearch -R /elasticsearch/config/certs

# yq and config-marger.sh is used to merge custom configuration files.
RUN wget https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_amd64 && \
    mv yq_linux_amd64 /usr/bin/yq && chmod +x /usr/bin/yq
COPY config-merger.sh /usr/bin/config-merger.sh

# runit.sh run at Entrypoint
COPY runit.sh /runit.sh

# Volume for Elasticsearch data
VOLUME ["/data"]

# Export HTTP & Transport
EXPOSE 9200 9300

# Run "runit.sh" on start
ENTRYPOINT ["/runit.sh"]
