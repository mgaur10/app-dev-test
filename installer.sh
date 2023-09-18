#!/bin/bash
set -e

if [ -z "$SERVICE_ACCOUNT" ]; then
  echo "Please enter your Service Account email with access to Assured OSS Maven Repositories:"
  read -r SERVICE_ACCOUNT
fi

if [ -z "$PROJECT_HOME" ]; then
  CURRENT_DIR="$(pwd)"
  echo "Please enter your project home directory where your skaffold.yaml configuration exists (default: ${CURRENT_DIR})"
  read -r PROJECT_HOME
  PROJECT_HOME=${PROJECT_HOME:-${CURRENT_DIR}}
fi

# Configure Maven Settings
M2_USER_HOME_SETTINGS="${HOME}/.m2/settings.xml"
if [ ! -f "$M2_USER_HOME_SETTINGS" ]; then
  mkdir -p ~/.m2
  cp "${PROJECT_HOME}/config/maven_settings.xml" "${M2_USER_HOME_SETTINGS}"
fi

if [ ! -f "~/.hello-world-dev-config" ]; then
  cp "${PROJECT_HOME}/config/hello-world-dev-config.sh" "${HOME}/.hello-world-dev-config"
fi

echo "source ~/.hello-world-dev-config \"$SERVICE_ACCOUNT\" \"$PROJECT_HOME\"" >> ~/.bashrc
echo "To finish installation, please source your ~/.hello-world-dev-config file or open a new shell"
echo "$ source ~/.hello-world-dev-config $SERVICE_ACCOUNT $PROJECT_HOME"
