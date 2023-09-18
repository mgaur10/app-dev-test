Hello README.md

## Prerequisites
1. Create a service account and register it with the Assured OSS team

```BASH
# Replace or set DEVELOPER_SERVICE_ACCOUNT to your own value
gcloud iam service-accounts create $DEVELOPER_SERVICE_ACCOUNT \
    --description="inner/outer dev loop service agent" \
    --display-name="Assured OSS Account"

# Get the fully qualified email address of the Service account to use below
gcloud iam service-accounts list --format 'value(email)'
```
* Assured OSS registration: https://developers.google.com/assured-oss?utm_source=CGC&utm_medium=referral#get-started


2. Set the environment variables for the registered service account and the Google Cloud project where your pipeline components will be deployed.

```BASH
export DEVELOPER_SERVICE_ACCOUNT=<DEVELOPER_SERVICE_ACCOUNT>
export PROJECT_ID=<YOUR-PROJECT-ID>
export PROJECT_NUMBER=<YOUR-PROJECT-NUMBER>
export END_USER_ACCOUNT=<YOUR-LOGIN-ACCOUNT>
```

## Instructions

#### Configure Access

1. Enable required services

```BASH
gcloud config set project $PROJECT_ID

SERVICES=(artifactregistry.googleapis.com
autoscaling.googleapis.com
binaryauthorization.googleapis.com
cloudapis.googleapis.com
cloudbuild.googleapis.com
clouddeploy.googleapis.com
cloudkms.googleapis.com
cloudtrace.googleapis.com
compute.googleapis.com
container.googleapis.com
containeranalysis.googleapis.com
containerfilesystem.googleapis.com
containerregistry.googleapis.com
containerscanning.googleapis.com
datastore.googleapis.com
dns.googleapis.com
iam.googleapis.com
iamcredentials.googleapis.com
logging.googleapis.com
monitoring.googleapis.com
networkconnectivity.googleapis.com
ondemandscanning.googleapis.com
oslogin.googleapis.com
pubsub.googleapis.com
servicemanagement.googleapis.com
servicenetworking.googleapis.com
serviceusage.googleapis.com
sourcerepo.googleapis.com
sql-component.googleapis.com
storage-api.googleapis.com
storage-component.googleapis.com
storage.googleapis.com
workstations.googleapis.com)
for SERVICE in ${SERVICES[@]}; do
  gcloud services enable $SERVICE
done
```

2. Set permissions on the service account

```BASH
ROLES=(roles/artifactregistry.writer
roles/binaryauthorization.attestorsViewer
roles/cloudbuild.builds.builder
roles/clouddeploy.releaser
roles/clouddeploy.serviceAgent
roles/cloudkms.signerVerifier
roles/containeranalysis.notes.attacher
roles/containeranalysis.occurrences.editor
roles/containeranalysis.notes.occurrences.viewer
roles/logging.logWriter
roles/ondemandscanning.admin
roles/storage.objectCreator
roles/storage.objectViewer)
for ROLE in ${ROLES[@]}; do
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${DEVELOPER_SERVICE_ACCOUNT} \
  --role=$ROLE
done
```

3. Add Service Account impersonation roles to your end user account for your project

```BASH
ROLES=(roles/iam.serviceAccountUser
roles/iam.serviceAccountTokenCreator
roles/iam.serviceAccountAdmin)
for ROLE in ${ROLES[@]}; do
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=user:${END_USER_ACCOUNT} \
  --role=$ROLE
done
```

4. Add roles to the default compute service account (used for Cloud Deploy)

```BASH
ROLES=(roles/clouddeploy.serviceAgent
roles/cloudbuild.serviceAgent
roles/container.serviceAgent
roles/logging.logWriter
roles/storage.objectCreator
roles/storage.objectViewer)
for ROLE in ${ROLES[@]}; do
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --role=$ROLE
done
```

#### Configure Inner Dev Loop Instructure
1. Create or use an existing VPC with a Subnet and firewall rules for the Cloud Workstation
* To add Cloud Workstations to an existing Shared VPC, visit: https://cloud.google.com/workstations/docs/set-up-shared-vpc-access
* To learn more about the firewall rules required for Cloud Workstations, visit: https://cloud.google.com/workstations/docs/configure-firewall-rules

```BASH
gcloud compute networks create hello-world-network \
  --subnet-mode custom

gcloud compute networks subnets create hello-world-cluster-subnet \
  --network hello-world-network \
  --range 192.168.0.0/20 \
  --secondary-range pods-range=10.4.0.0/14,service-range=10.0.32.0/20 \
  --enable-private-ip-google-access \
  --region us-central1

gcloud compute firewall-rules create allow-all-internal \
  --network hello-world-network \
  --allow tcp,udp,icmp \
  --source-ranges 192.168.0.0/20

gcloud compute firewall-rules create allow-egress-workstations-control-plane \
  --network hello-world-network \
  --direction egress \
  --allow tcp:443,tcp:980 \
  --target-tags cloud-workstations-instance \
  --destination-ranges 0.0.0.0/0

2. Create the GKE Autopilot Cluster (Cluster creation may take approximately 10 minutes)

gcloud container clusters create-auto hello-world-cluster \
  --region us-central1 \
  --enable-master-authorized-networks \
  --network hello-world-network \
  --subnetwork hello-world-cluster-subnet \
  --cluster-secondary-range-name pods-range \
  --services-secondary-range-name service-range \
  --enable-private-nodes \
  --enable-private-endpoint \
  --master-ipv4-cidr 172.16.0.0/28
```

3. Create Cloud DNS entries where applicable

Note: If your organization does not allow external IP addresses and requires the use of private clusters, the following minimum domains must be included in your DNS records for Private Google Access:
- *.source.developers.google.com
- *.googleapis.com
- *.gcr.io
- *.pkg.dev

```BASH
gcloud dns managed-zones create source-google-com \
  --description="Cloud Source Repositories" \
  --dns-name="source.developers.google.com." \
  --visibility="private" \
  --networks="hello-world-network"

gcloud dns record-sets create "*.source.developers.google.com." \
  --rrdatas="source.developers.google.com." \
  --type=CNAME \
  --ttl=300 \
  --zone=source-google-com

gcloud dns record-sets create "source.developers.google.com." \
  --rrdatas="199.36.153.8,199.36.153.9,199.36.153.10,199.36.153.11" \
  --type=A \
  --ttl=300 \
  --zone=source-google-com

gcloud dns managed-zones create googleapis-com \
  --description="Google APIs" \
  --dns-name="googleapis.com." \
  --visibility="private" \
  --networks="hello-world-network"

gcloud dns record-sets create "*.googleapis.com." \
  --rrdatas="googleapis.com." \
  --type=CNAME \
  --ttl=300 \
  --zone=googleapis-com

gcloud dns record-sets create "googleapis.com." \
  --rrdatas="199.36.153.8,199.36.153.9,199.36.153.10,199.36.153.11" \
  --type=A \
  --ttl=300 \
  --zone=googleapis-com

gcloud dns managed-zones create gcr-io \
  --description="Google Container Registry" \
  --dns-name="gcr.io." \
  --visibility="private" \
  --networks="hello-world-network"

gcloud dns record-sets create "*.gcr.io." \
  --rrdatas="gcr.io." \
  --type=CNAME \
  --ttl=300 \
  --zone=gcr-io

gcloud dns record-sets create "gcr.io" \
  --rrdatas="199.36.153.8,199.36.153.9,199.36.153.10,199.36.153.11" \
  --type=A \
  --ttl=300 \
  --zone=gcr-io

gcloud dns managed-zones create pkg-dev \
  --description="Google Artifact Registry" \
  --dns-name="pkg.dev." \
  --visibility="private" \
  --networks="hello-world-network"

gcloud dns record-sets create "*.pkg.dev." \
  --rrdatas="pkg.dev." \
  --type=CNAME \
  --ttl=300 \
  --zone=pkg-dev

gcloud dns record-sets create "pkg.dev" \
  --rrdatas="199.36.153.8,199.36.153.9,199.36.153.10,199.36.153.11" \
  --type=A \
  --ttl=300 \
  --zone=pkg-dev
```

4. Create a Cloud Workstation (Cluster, Config, Instance and any required components) and use the networking from the VPC and subnet mentioned in the previous step.

```BASH
gcloud workstations clusters create workstation-cluster \
  --region=us-central1 \
  --network="projects/${PROJECT_ID}/global/networks/hello-world-network" \
  --subnetwork="projects/${PROJECT_ID}/regions/us-central1/subnetworks/hello-world-cluster-subnet"

gcloud workstations configs create workstation-config \
  --machine-type e2-standard-4 \
  --shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --disable-public-ip-addresses \
  --region us-central1 \
  --cluster workstation-cluster

gcloud workstations create hello-world-workstation \
  --cluster workstation-cluster \
  --config workstation-config \
  --region us-central1

 gcloud workstations start hello-world-workstation \
   --region us-central1 \
   --cluster workstation-cluster \
   --config workstation-config
```

#### Configure Your Cloud Workstations

Launch your Cloud Workstation and open a Terminal

Note: The following commands should be run from a Terminal inside your Cloud Workstation

1. Configure gcloud
```BASH
gcloud init
```

1. Create and clone a Cloud Source Repository
```BASH
gcloud source repos create hello-world-java
gcloud source repos clone hello-world-java

# Configure git 
git config --global user.email "[YOUR_EMAIL]"
git config --global user.name "[YOUR_NAME]"
```

3. Clone the copy over base files from the spring-java-hello-world base project 
```BASH
#NOTE: We'll need to find a more permenant GCP project or other Git repository
gcloud source repos clone springboard-java-hello-world --project springboard-dev-env --branch main
pushd .
  cd springboard-java-hello-world
  git checkout main
popd
cp -r springboard-java-hello-world/* \
      springboard-java-hello-world/.mvn \
      springboard-java-hello-world/.gitignore \
      hello-world-java/

cd hello-world-java
git add .
git commit -m "first commit"
```

4. Run the installer script
```BASH
./installer.sh
```
Note: The installer script will alter your ~/.bashrc file.

5. Source your ~/.hello-world-dev-config file to set your env vars in your local shell
```BASH
source ~/.hello-world-dev-config
```
Note: Your ~/.bashrc has been configured to source ~/.hello-world-dev-config, which will start minikube, skaffold (in dev mode), configure docker, and configure maven home directories. This allows every new terminal or shell that you open to maintain a consistent configuration.

#### Use The Inner Dev Loop


##### Continuous Deployment to Minikube

The 'skaffold dev' process is expected to be running in the background to automate the building to local docker and deploying to minikube. The skaffold process is expected to have started after opening a Cloud Workstation terminal and is expected to run without crashing. If the skaffold process has crashed it will either need to be started again manually or by opening another terminal window in you Cloud Workstation. The same applies for the Minikube cluster.

During the first build of the application on the Cloud Workstation, skaffold may take ~1 minute to build and fetch all the application dependencies. Please check the status of the status of the skaffold build by viewing /var/logs/skaffold.log and/or checking the status of the k8s resources on minikube. The following steps will only work if the minikube resources (Service, Deployment, etc) are running.

1. Access the local minikube k8s service through the web browser via port-forwarding: 

```BASH
kubectl port-forward services/spring-java-hello-world-service 5000:8080
```

2. Validate that the app is running correctly

```BASH
# should see a Hello World message
curl http://localhost:5000/"
```

3. Access your app through the external Cloud Workstations Preview network

Ctrl+click on the "http://localhost:5000/" link rendered in the Cloud Workstation terminal. A web browser tab will open to a URL for the public gateway of your Cloud Workstation and you will see the response.

After Ctrl+Clicking the localhost link your browser should open a tab to the and access your app through a URL that follows a similar format:
https://5000-[workstation-name].[cluster-id].cloudworkstations.dev/

NOTE: You will need a valid access token to access the your Cloud Workstation preview network. If you experience an 'Invalid Token' response and you are signed in to multiple Google accounts, add the 'authuser=1' (or the particular authuser value for the account you like to use) to the query string of the authorization error page.

4. Make a change to the src/main/java/com/example/helloWorld/HelloWorldApplication.java

```JAVA
        return "Hello World [myname]!";
```

NOTE: The file is expected to autosave, which will trigger a Skaffold build. No git commit is required.

5. Wait roughly 30 seconds for Skaffold to build and deploy the application to minikube.

6. Refresh the browser window open for "*.*.cloudworkstations.dev" and see the changes

7. (Optional) Validate that you can access the pod through the k8 service on minikube

```BASH
MINIKUBE_IP=$(minikube ip)
SERVICE_PORT=$(kubectl get svc spring-java-hello-world-service -o jsonpath='{.spec.ports[0].nodePort}')
curl "http://${MINIKUBE_IP}:${SERVICE_PORT}/"
```

##### Continuous Deployment to Java Process

This inner dev loop process is enabled through Spring Boot Hot Reloading. Changes to the local Spring Boot Java and related files will be loaded directly into the running Java process. There is no containerization or k8s deployment in this workflow. This workflow is most useful for getting rapid feedback during a development cycle. However, the container deployed to Minikube should be considered a more accurate source of truth.

1. Install the maven dependencies
```BASH
./mvnw install
```

Note: Maven packages will be pull from the OSS Assured Maven repository. The installer.sh script will have configured your Service Account Access token that is referenced by your ~/.m2/settings.xml file to authenticate to the OSS Assured Maven repositories.

2. Start up the app directly from the JAR
```BASH
./mvnw spring-boot:run
```

3. Validate that the app is running correctly
```BASH
# open another termial so that the app can run in the foreground of the current terminal
curl http://localhost:8080/
```

4. Access your app through the external Cloud Workstations Preview network:

Click the http://localhost:8080/ rendered in the Workstation terminal form the previous step.

After Ctrl+Clicking the localhost link your browser should open a tab to the and access your app through a URL that follows a similar format:
https://8080-[workstation-name].[cluster-id].cloudworkstations.dev/

#### Configure Outer Dev Loop Instructure

## Before you begin
To maintain optimal compatibility and streamline the deployment process, we strongly advise keeping all the components and resources associated with this project within a single Google Cloud project. This approach helps maintain a cohesive environment, allowing components to interact seamlessly and reduces the likelihood of compatibility issues.

If separation of duties and additional organization is needed, it is best to isolate the GKE cluster within its dedicated project, ensuring efficient cluster management and specialized access controls. On the other hand, it is highly advise keeping the remaining software supply chain pipeline components - such as Cloud Build, Artifact Registry, and CI/CD tools - contained within a single project.

## Deploy outer dev loop

#### Prerequisites

1. Create or use an existing VPC with a Subnet for the GKE Cluster 

2. Create a private GKE cluster using the VPC and Subnet created in the last step.

3. Note for Argolis users:

You will first need to override the default 'denyAll' policy and change it ot 'allowAll' for the following constraint:

```
constraints/compute.restrictVpnPeerIPs
```

#### Steps

1. Create the Networking infrastruce to enable Cloud Build Private Worker Pools to communicate with private GKE cluster control plane.

```BASH
# Replace the variables within this script
./create-cloud-build-networking.sh
```

2. Create a Docker Repository in Artifact Registry

```BASH
gcloud artifacts repositories create hello-world-docker-repository \
  --repository-format=docker \
  --location=us-central1 \
  --description="Sample Hello World Docker repo"
```

3. Add permissions the service account to the Cloud Source Repository for your sample app.

```BASH
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$DEVELOPER_SERVICE_ACCOUNT" \
  --role="roles/source.reader" \
  --project=$PROJECT_ID
```

4. Create an Attestor for Binary Authorization

```BASH
# Replace the environment variables at the top of the script with your values.
./create-attestor
```

5. Enable Binary Authorization on the GKE Cluster

```BASH
# Replace the $PROJECT_ID value in config/binauthz_policy.yaml with your own and then import the policy 
gcloud container clusters get-credentials hello-world-cluster --region us-central1
gcloud container binauthz policy import config/binauthz_policy.yaml
# configure dev cluster back to 'minikube'
kubectl config set-cluster minikube
```

#### Outer Dev Loop Setup Guide

The Outer Dev loop enables Continuous Deployment to your private GKE Cluster 

1. Replace values in cloudbuild.yaml and clouddeploy.yml with our own

2. Create the Cloud Deploy Pipeline

```BASH
gcloud deploy apply --file=clouddeploy.yml --region=us-central1 --project=$PROJECT_ID
```

3. Create the Cloud Build Trigger
```BASH
gcloud beta builds triggers create cloud-source-repositories \
  --name=cloudbuild-launcher-trigger \
  --project=$PROJECT_ID \
  --repo=projects/$PROJECT_ID/repos/hello-world-java \
  --branch-pattern=master \
  --region=us-central1 \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$DEVELOPER_SERVICE_ACCOUNT \
  --build-config=cloudbuild-launcher.yaml \
  --substitutions='_REPO_URL=$(csr.url)'
```

##### Run through the Outer Dev Loop

1. Commit and push changes to the Code Repository 'main' branch

2. Validate that a new container built in Artifact Registry (optional)

3. Validate that a new Cloud Deploy release was created and ran successfully (optional)

4. Validate that a Container Scan ran and found no HIGH or CRITICAL severity vulnerabilities. (optional)

5. Validate that an Attestation was created for the new container (optional)

6. Validate that your new Deployment is running on GKE

```BASH
kubectl port-forward services/spring-java-hello-world-service 5000:8080
# open a new terminal in your Cloud Workstation so the previous command can run in the foreground
curl http://localhost:5000/
# You should see a "Hello World" response here
```

#### Command Reference
These commands are here for reference and are in no particular order.

1. Build the application container. This happens automatically through skaffold.
```BASH
./mvnw compile jib:dockerBuild
```

2. Apply the k8s manifest. This happens automatically through skaffold.
```BASH
kubectl apply -f kubernetes/deployment.yml
```

3. Submit the build manually
```BASH
#TODO: this command will soon be replaced by a build trigger
gcloud builds submit --region=us-central1 --config cloudbuild.yaml . # note: '.' is the location of your local codebase working directory.
```

2. Run the Trigger Manually
```BASH
#TODO: add gcloud to run the trigger, or instructions to run through Cloud Console UI
```

### Notes on Service Accounts and Permissions

1. The Service account used for Cloud Build is the same account registered with the OSS Assured Maven Repository. Here is the account information and roles:

2. The Service Acccount used to invoke the Cloud Deploy pipeline is the default GCP generated account for Cloud Deploy on the project. Here is the account information and roles:

3. The Service account used in the Cloud Deploy steps is the default GCP generated account Service Account (for all compute services) for the project. Here is the account information and roles:

### Issues ###

1) When running the create-cloud-build-networking.sh script there is an error when creating the vpn-tunnels to connect the Cloud Build Worker Pool to the private GKE cluster:

Workaround

Disable the "constraints/compute.restrictVpnPeerIPs" Organization Policy Constraint. TODO: We should be able to peer the vpn-tunnels without violating this constraint.. find a way to do it. 
