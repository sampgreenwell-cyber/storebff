FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline
COPY src ./src
# Tests run in the pipeline's CI job; the image build only packages.
RUN mvn -B -ntp -DskipTests package \
 && JAR=$(find target -maxdepth 1 -type f -name "*.jar" ! -name "*.original" | head -n 1) \
 && cp "$JAR" /workspace/app.jar \
 && curl -fsSLo /workspace/dd-java-agent.jar https://dtdg.co/latest-java-tracer

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/app.jar /app/app.jar
COPY --from=build /workspace/dd-java-agent.jar /app/dd-java-agent.jar
# DD_SERVICE / DD_ENV / DD_VERSION / DD_TAGS / DD_TRACE_ENABLED are set per environment
# by infra/main.bicep. Traces go to the Datadog Agent sidecar on 127.0.0.1:8126 when
# enableDatadogSidecar is on; otherwise tracing is disabled.
ENV DD_SITE=datadoghq.com
# Inject trace/span IDs into log lines.
ENV DD_LOGS_INJECTION=true
# Non-root (the ubuntu user in the Temurin base image).
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java", "-javaagent:/app/dd-java-agent.jar", "-jar", "/app/app.jar"]
