# Multi-stage so the runtime image carries a JRE and a jar, not a JDK and a Maven
# cache. Layer order matters: dependencies resolve in their own layer keyed on
# pom.xml, so a source-only change does not re-download the world.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# App Runner runs the container as given; dropping root is ours to do.
RUN addgroup -S app && adduser -S app -G app
USER app

COPY --from=build /build/target/*.jar app.jar

EXPOSE 8080

# Container-aware heap sizing. Without this the JVM can size itself against the
# host's memory rather than the container limit and get killed under load.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+UseSerialGC"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
