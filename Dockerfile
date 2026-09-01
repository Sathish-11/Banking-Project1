FROM maven:3.8.4-openjdk-17 AS builder

WORKDIR /app

COPY .mvn pom.xml ./

COPY src ./src

RUN mvn clean package -DskipTests

FROM eclipse-temurin:25

WORKDIR /app

COPY --from=builder /app/target/*.jar ./app.jar

EXPOSE 8081

ENTRYPOINT ["java", "-jar","/app/app.jar"]

