#!/bin/bash

# TODO: Replace this value with the Service Account principal that has permission to access OSS Assured Maven Repositories
# SERVICE_ACCOUNT="oss-assured-service-account@springboard-dev-env.iam.gserviceaccount.com"

if [ "$#" -ne 2 ]; then
  echo "2 Arguments are required: <SERVICE_ACCOUNT> <PROJECT_HOME>"
  exit # Exit with 0 to not block shell initialization
fi

export SERVICE_ACCOUNT=$1
export PROJECT_HOME=$2

# used by maven to acccess Assured OSS repos
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --impersonate-service-account=${SERVICE_ACCOUNT} --verbosity=error)"

export MVN_VERSION="3.8.7"
export M2_HOME="/opt/apache-maven/apache-maven-${MVN_VERSION}"
# required so mvnw installs in the right place
export MAVEN_USER_HOME="$M2_HOME"
# Use for debugging
export MVNW_VERBOSE=true
export PATH="${M2_HOME}/bin:${PATH}"

if [ ! -f "$M2_HOME.zip" ]; then
  sudo mkdir -p /opt/apache-maven
  sudo chown user:user /opt/apache-maven/

  echo "Downloading apache maven..."
  # See https://maven.apache.org/wrapper/ for docs
  curl -s -L -H "Authorization: Bearer $GOOGLE_OAUTH_ACCESS_TOKEN" \
    https://us-maven.pkg.dev/cloud-aoss/java/org/apache/maven/apache-maven/${MVN_VERSION}/apache-maven-${MVN_VERSION}-bin.zip \
    --output "$M2_HOME.zip"
fi

if [ ! -f "/var/log/minikube.log" ]; then
  sudo touch /var/log/minikube.log
  sudo chown user:user /var/log/minikube.log
fi

if [ ! -f "/var/log/skaffold.log" ]; then
  sudo touch /var/log/skaffold.log
  sudo chown user:user /var/log/skaffold.log
fi

startMinikube() {
  daemonize=$1
  if [ "$daemonize" = "-d" ]; then
    minikube start >> /var/log/minikube.log 2>&1 &
  else
    minikube start 2>&1 | tee -a /var/log/minikube.log
  fi
}
export -f startMinikube

if [[ ! $(pgrep -f minikube) ]]; then
  echo "Starting minikube..."
  sudo touch /var/log/minikube.log
  sudo chown user:user /var/log/minikube.log
  startMinikube "-d"
  echo "logging to: /var/log/minikube.log"
fi
#TODO: ensure minikube is running before this command
eval $(minikube docker-env)

startSkaffold() {
  daemonize=$1
  if [ "$daemonize" = "-d" ]; then
    skaffold dev -f ${PROJECT_HOME}/skaffold.yaml -p dev --trigger notify >> /var/log/skaffold.log 2>&1 &
  else
    skaffold dev -f ${PROJECT_HOME}/skaffold.yaml -p dev --trigger notify 2>&1 | tee -a /var/log/skaffold.log
  fi
}
export -f startSkaffold

if [[ ! $(pgrep -f skaffold) ]]; then
  echo "Starting skaffold dev..."
  sudo touch /var/log/skaffold.log
  sudo chown user:user /var/log/skaffold.log
  startSkaffold "-d"
  echo "logging to: /var/log/skaffold.log"
fi
