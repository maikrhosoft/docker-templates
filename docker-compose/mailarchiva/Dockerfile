FROM tomcat:10.1-jre21-temurin

ENV MAILARCHIVA_VERSION=10.1.0
ENV MAILARCHIVA_HOME=/opt/mailarchiva
ENV MAILARCHIVA_WAR_URL=https://stimulussoft.b-cdn.net/mailarchiva-10.1.0.war

RUN apt-get update && \
    apt-get install -y wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p $MAILARCHIVA_HOME/data $MAILARCHIVA_HOME/logs

WORKDIR /usr/local/tomcat

RUN rm -rf webapps/* \
    && wget -O webapps/ROOT.war "$MAILARCHIVA_WAR_URL" \
    && test -s webapps/ROOT.war

EXPOSE 8080

CMD ["catalina.sh", "run"]
