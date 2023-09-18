#!/bin/bash
set -ex

# From: https://cloud.google.com/binary-authorization/docs/creating-attestors-cli

if [[ -z "$PROJECT_ID" ]]; then
  echo "You must set PROJECT_ID env var"
  exit 1
fi

if [[ -z "$SERVICE_ACCOUNT" ]]; then
  echo "You must set SERVICE_ACCOUNT env var"
  exit 1
fi

# Set these variables for your environment
DEPLOYER_PROJECT_ID=$PROJECT_ID
ATTESTOR_PROJECT_ID=$PROJECT_ID
DEPLOYER_SERVICE_ACCOUNT=$SERVICE_ACCOUNT
ATTESTOR_SERVICE_ACCOUNT=$SERVICE_ACCOUNT
# End user definited variables

DEPLOYER_PROJECT_NUMBER="$(
    gcloud projects describe "${DEPLOYER_PROJECT_ID}" \
      --format="value(projectNumber)"
)"

ATTESTOR_PROJECT_NUMBER="$(
    gcloud projects describe "${ATTESTOR_PROJECT_ID}" \
    --format="value(projectNumber)"
)"

NOTE_ID=springboard-hello-world-attestor-note
NOTE_URI="projects/${ATTESTOR_PROJECT_ID}/notes/${NOTE_ID}"
DESCRIPTION="Attestor note for the Springboard Hello World Java app"

cat > /tmp/note_payload.json << EOM
{
  "name": "${NOTE_URI}",
  "attestation": {
    "hint": {
      "human_readable_name": "${DESCRIPTION}"
    }
  }
}
EOM

curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)"  \
    -H "x-goog-user-project: ${ATTESTOR_PROJECT_ID}" \
    --data-binary @/tmp/note_payload.json  \
    "https://containeranalysis.googleapis.com/v1/projects/${ATTESTOR_PROJECT_ID}/notes/?noteId=${NOTE_ID}"

# Verify that the command worked
curl \
    -H "Authorization: Bearer $(gcloud auth print-access-token)"  \
    -H "x-goog-user-project: ${ATTESTOR_PROJECT_ID}" \
    "https://containeranalysis.googleapis.com/v1/projects/${ATTESTOR_PROJECT_ID}/notes/"

cat > /tmp/iam_request.json << EOM
{
  "resource": "${NOTE_URI}",
  "policy": {
    "bindings": [
      {
        "role": "roles/containeranalysis.notes.occurrences.viewer",
        "members": [
          "serviceAccount:${ATTESTOR_SERVICE_ACCOUNT}"
        ]
      }
    ]
  }
}
EOM

curl -X POST  \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: ${ATTESTOR_PROJECT_ID}" \
    --data-binary @/tmp/iam_request.json \
    "https://containeranalysis.googleapis.com/v1/projects/${ATTESTOR_PROJECT_ID}/notes/${NOTE_ID}:setIamPolicy"

KMS_KEY_PROJECT_ID=springboard-dev-env
KMS_KEY_LOCATION=us-central1
KMS_KEYRING_NAME=springboard-keyring
KMS_KEY_NAME=springboard-key
KMS_KEY_VERSION=1
KMS_KEY_PURPOSE=asymmetric-signing
KMS_KEY_ALGORITHM=ec-sign-p256-sha256
KMS_PROTECTION_LEVEL=software

gcloud kms keyrings create ${KMS_KEYRING_NAME} \
    --location ${KMS_KEY_LOCATION}

gcloud kms keys create ${KMS_KEY_NAME} \
    --location ${KMS_KEY_LOCATION} \
    --keyring ${KMS_KEYRING_NAME}  \
    --purpose ${KMS_KEY_PURPOSE} \
    --default-algorithm ${KMS_KEY_ALGORITHM} \
    --protection-level ${KMS_PROTECTION_LEVEL}

ATTESTOR_NAME=springboard-hello-world-attestor

gcloud --project="${ATTESTOR_PROJECT_ID}" \
    container binauthz attestors create "${ATTESTOR_NAME}" \
    --attestation-authority-note="${NOTE_ID}" \
    --attestation-authority-note-project="${ATTESTOR_PROJECT_ID}"

gcloud container binauthz attestors add-iam-policy-binding \
    "projects/${ATTESTOR_PROJECT_ID}/attestors/${ATTESTOR_NAME}" \
    --member="serviceAccount:${DEPLOYER_SERVICE_ACCOUNT}" \
    --role=roles/binaryauthorization.attestorsVerifier

gcloud --project="${ATTESTOR_PROJECT_ID}" \
    container binauthz attestors public-keys add \
    --attestor="${ATTESTOR_NAME}" \
    --keyversion-project="${KMS_KEY_PROJECT_ID}" \
    --keyversion-location="${KMS_KEY_LOCATION}" \
    --keyversion-keyring="${KMS_KEYRING_NAME}" \
    --keyversion-key="${KMS_KEY_NAME}" \
    --keyversion="${KMS_KEY_VERSION}"

PUBLIC_KEY_ID=$(gcloud container binauthz attestors describe ${ATTESTOR_NAME} \
--format='value(userOwnedGrafeasNote.publicKeys[0].id)')

# Validate that the attestor was created
gcloud container binauthz attestors list \
    --project="${ATTESTOR_PROJECT_ID}"
