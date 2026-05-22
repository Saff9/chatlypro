# Chatly Android build container.
#
# We do NOT use upstream's Dockerfile directly: at release-11.4.2-5469 it
# uses gradle:7.0.2-jdk11 as the base, but the source tree at that tag pins
# AGP 8.4.2, which requires Gradle 8.6+. That's an upstream inconsistency.
#
# This image uses Gradle 8.7 on JDK 17 (matches what AGP 8.4 needs) plus
# Android SDK 33 + NDK 21.4.7075529 (matches what upstream's Dockerfile asks
# for via sdkmanager).

FROM gradle:8.7-jdk17

ENV ANDROID_SDK_URL=https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
ENV ANDROID_API_LEVEL=android-33
ENV ANDROID_BUILD_TOOLS_VERSION=33.0.0
ENV ANDROID_HOME=/usr/local/android-sdk-linux
ENV ANDROID_SDK_ROOT=/usr/local/android-sdk-linux
ENV ANDROID_NDK_VERSION=21.4.7075529
ENV ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}/
ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_NDK_HOME}:${ANDROID_NDK_HOME}/prebuilt/linux-x86_64/bin

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl unzip ca-certificates git python3 && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$ANDROID_HOME" && \
    cd "$ANDROID_HOME" && \
    curl -fsSL -o sdk.zip "$ANDROID_SDK_URL" && \
    unzip -q sdk.zip && \
    rm sdk.zip && \
    mkdir -p cmdline-tools/latest && \
    mv cmdline-tools/* cmdline-tools/latest/ 2>/dev/null || true

RUN yes | "$ANDROID_HOME"/cmdline-tools/latest/bin/sdkmanager --sdk_root="$ANDROID_HOME" --licenses
RUN "$ANDROID_HOME"/cmdline-tools/latest/bin/sdkmanager --sdk_root="$ANDROID_HOME" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
        "platforms;${ANDROID_API_LEVEL}" \
        "platform-tools" \
        "ndk;${ANDROID_NDK_VERSION}"

# Provide a /home/gradle workdir like upstream's image expects.
RUN mkdir -p /home/gradle && chmod 0777 /home/gradle
WORKDIR /home/gradle
