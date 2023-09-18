#!/bin/bash
set -ex

# Solution architecture guide as a basis for this script
# [1] https://cloud.google.com/architecture/accessing-private-gke-clusters-with-cloud-build-private-pools
# Detailed instructions on HA VPN setup between two VPCs (required for this integration)
# [2] https://cloud.google.com/network-connectivity/docs/vpn/how-to/creating-ha-vpn2#gcloud_5

# --- Vars for local script
if [[ -z "$VPN_SHARED_SECRET" ]]; then
    echo "You must set VPN_SHARED_SECRET in environment: https://cloud.google.com/network-connectivity/docs/vpn/how-to/generating-pre-shared-key" 1>&2
    exit 1
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "You must set PROJECT_ID env var"
  exit 1
fi

# Project ID of the project containing the Private GKE Cluster
GKE_CLUSTER_PROJECT=$PROJECT_ID
# Private GKE Cluster for deployment
GKE_CLUSTER_NAME=hello-world-cluster
# VPC used for the Private GKE cluster
VPC_NAME=hello-world-network

VPC_HOST_PROJECT="$GKE_CLUSTER_PROJECT"
VPC_HOST_PROJECT_NUMBER="$(gcloud projects describe $VPC_HOST_PROJECT --format 'value(projectNumber)')" 
# --- End Vars for local script

PRIVATE_POOL_PEERING_VPC_NAME=hello-world-cloud-build-central-vpc
RESERVED_RANGE_NAME=private-pool-addresses
PRIVATE_POOL_NETWORK=192.168.16.0
PRIVATE_POOL_PREFIX=20
PRIVATE_POOL_NAME=hello-world-private-pool
REGION=us-central1
CLUSTER_CONTROL_PLANE_CIDR=172.16.0.0/28

NETWORK_1=$PRIVATE_POOL_PEERING_VPC_NAME
NETWORK_2=$VPC_NAME

GW_NAME_1=private-peer-gateway
GW_NAME_2=gke-central-gateway
PEER_ASN_1=65001
PEER_ASN_2=65002

IP_ADDRESS_1=169.254.2.1
IP_ADDRESS_2=169.254.3.1
IP_ADDRESS_3=169.254.2.2
IP_ADDRESS_4=169.254.3.2

PEER_IP_ADDRESS_1=$IP_ADDRESS_3
PEER_IP_ADDRESS_2=$IP_ADDRESS_4
PEER_IP_ADDRESS_3=$IP_ADDRESS_1
PEER_IP_ADDRESS_4=$IP_ADDRESS_2

ROUTER_NAME_1=cloud-build-router
ROUTER_1_INTERFACE_NAME_0=cloud-build-interface-if0
ROUTER_1_INTERFACE_NAME_1=cloud-build-interface-if1
TUNNEL_NAME_GW1_IF0=gke-central-tunnel-if0
TUNNEL_NAME_GW1_IF1=gke-central-tunnel-if1
PEER_NAME_GW1_IF0=cloud-build-peer-if0
PEER_NAME_GW1_IF1=cloud-build-peer-if1

ROUTER_NAME_2=gke-central-router
ROUTER_2_INTERFACE_NAME_0=gke-central-interface-if0
ROUTER_2_INTERFACE_NAME_1=gke-central-interface-if1
TUNNEL_NAME_GW2_IF0=cloud-build-tunnel-if0
TUNNEL_NAME_GW2_IF1=cloud-build-tunnel-if1
PEER_NAME_GW2_IF0=gke-central-peer-if0
PEER_NAME_GW2_IF1=gke-central-peer-if1

MASK_LENGTH=30
SHARED_SECRET=$VPN_SHARED_SECRET

gcloud config set project $GKE_CLUSTER_PROJECT
gcloud config set compute/region $REGION

export GKE_PEERING_NAME=$(gcloud container clusters describe $GKE_CLUSTER_NAME \
  --region=$REGION \
  --format='value(privateClusterConfig.peeringName)')
echo $GKE_PEERING_NAME 

gcloud compute networks create $PRIVATE_POOL_PEERING_VPC_NAME \
  --subnet-mode=CUSTOM

gcloud compute addresses create $RESERVED_RANGE_NAME \
  --global \
  --purpose=VPC_PEERING \
  --addresses=$PRIVATE_POOL_NETWORK \
  --prefix-length=$PRIVATE_POOL_PREFIX \
  --network=$PRIVATE_POOL_PEERING_VPC_NAME

gcloud compute networks peerings update $GKE_PEERING_NAME \
  --network=$VPC_NAME \
  --export-custom-routes \
  --no-export-subnet-routes-with-public-ip

gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=$RESERVED_RANGE_NAME \
  --network=$PRIVATE_POOL_PEERING_VPC_NAME

gcloud compute networks peerings update servicenetworking-googleapis-com \
    --network=$PRIVATE_POOL_PEERING_VPC_NAME \
    --export-custom-routes \
    --no-export-subnet-routes-with-public-ip

gcloud builds worker-pools create $PRIVATE_POOL_NAME \
  --region=$REGION \
  --peered-network=projects/$VPC_HOST_PROJECT_NUMBER/global/networks/$PRIVATE_POOL_PEERING_VPC_NAME \
  --no-public-egress

gcloud compute vpn-gateways create $GW_NAME_1 \
   --network=$NETWORK_1 \
   --region=$REGION \
   --stack-type=IPV4_ONLY

gcloud compute vpn-gateways create $GW_NAME_2 \
   --network=$NETWORK_2 \
   --region=$REGION \
   --stack-type=IPV4_ONLY

gcloud compute routers create $ROUTER_NAME_1 \
   --region=$REGION \
   --network=$NETWORK_1 \
   --asn=$PEER_ASN_1

gcloud compute routers create $ROUTER_NAME_2 \
   --region=$REGION \
   --network=$NETWORK_2 \
   --asn=$PEER_ASN_2

gcloud compute vpn-tunnels create $TUNNEL_NAME_GW1_IF0 \
    --peer-gcp-gateway=$GW_NAME_2 \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$SHARED_SECRET \
    --router=$ROUTER_NAME_1 \
    --vpn-gateway=$GW_NAME_1 \
    --interface=0

gcloud compute vpn-tunnels create $TUNNEL_NAME_GW1_IF1 \
    --peer-gcp-gateway=$GW_NAME_2 \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$SHARED_SECRET \
    --router=$ROUTER_NAME_1 \
    --vpn-gateway=$GW_NAME_1 \
    --interface=1

gcloud compute vpn-tunnels create $TUNNEL_NAME_GW2_IF0 \
    --peer-gcp-gateway=$GW_NAME_1 \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$SHARED_SECRET \
    --router=$ROUTER_NAME_2 \
    --vpn-gateway=$GW_NAME_2 \
    --interface=0

gcloud compute vpn-tunnels create $TUNNEL_NAME_GW2_IF1 \
    --peer-gcp-gateway=$GW_NAME_1 \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$SHARED_SECRET \
    --router=$ROUTER_NAME_2 \
    --vpn-gateway=$GW_NAME_2 \
    --interface=1

gcloud compute routers add-interface $ROUTER_NAME_1 \
    --interface-name=$ROUTER_1_INTERFACE_NAME_0 \
    --ip-address=$IP_ADDRESS_1 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_NAME_GW1_IF0 \
    --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_NAME_1 \
    --peer-name=$PEER_NAME_GW1_IF0 \
    --interface=$ROUTER_1_INTERFACE_NAME_0 \
    --peer-ip-address=$PEER_IP_ADDRESS_1 \
    --peer-asn=$PEER_ASN_2 \
    --region=$REGION

gcloud compute routers add-interface $ROUTER_NAME_1 \
   --interface-name=$ROUTER_1_INTERFACE_NAME_1 \
   --ip-address=$IP_ADDRESS_2 \
   --mask-length=$MASK_LENGTH \
   --vpn-tunnel=$TUNNEL_NAME_GW1_IF1 \
   --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_NAME_1 \
    --peer-name=$PEER_NAME_GW1_IF1 \
    --interface=$ROUTER_1_INTERFACE_NAME_1 \
    --peer-ip-address=$PEER_IP_ADDRESS_2 \
    --peer-asn=$PEER_ASN_2 \
    --region=$REGION

gcloud compute routers describe $ROUTER_NAME_1  \
    --region=$REGION

gcloud compute routers add-interface $ROUTER_NAME_2 \
    --interface-name=$ROUTER_2_INTERFACE_NAME_0 \
    --ip-address=$IP_ADDRESS_3 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_NAME_GW2_IF0 \
    --region=$REGION
    
gcloud compute routers add-bgp-peer $ROUTER_NAME_2 \
    --peer-name=$PEER_NAME_GW2_IF0 \
    --interface=$ROUTER_2_INTERFACE_NAME_0 \
    --peer-ip-address=$PEER_IP_ADDRESS_3 \
    --peer-asn=$PEER_ASN_1 \
    --region=$REGION

gcloud compute routers add-interface $ROUTER_NAME_2 \
   --interface-name=$ROUTER_2_INTERFACE_NAME_1 \
   --ip-address=$IP_ADDRESS_4 \
   --mask-length=$MASK_LENGTH \
   --vpn-tunnel=$TUNNEL_NAME_GW2_IF1 \
   --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_NAME_2 \
    --peer-name=$PEER_NAME_GW2_IF1 \
    --interface=$ROUTER_2_INTERFACE_NAME_1 \
    --peer-ip-address=$PEER_IP_ADDRESS_4 \
    --peer-asn=$PEER_ASN_1 \
    --region=$REGION

gcloud compute routers describe $ROUTER_NAME_2  \
   --region=$REGION

gcloud compute routers update-bgp-peer $ROUTER_NAME_1 \
  --peer-name=$PEER_NAME_GW1_IF0 \
  --region=$REGION \
  --advertisement-mode=CUSTOM \
  --set-advertisement-ranges="$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX"
gcloud compute routers update-bgp-peer $ROUTER_NAME_1 \
  --peer-name=$PEER_NAME_GW1_IF1 \
  --region=$REGION \
  --advertisement-mode=CUSTOM \
  --set-advertisement-ranges="$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX"
gcloud compute routers update-bgp-peer $ROUTER_NAME_2 \
  --peer-name=$PEER_NAME_GW2_IF0 \
  --region=$REGION \
  --advertisement-mode=CUSTOM \
  --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR
gcloud compute routers update-bgp-peer $ROUTER_NAME_2 \
  --peer-name=$PEER_NAME_GW2_IF1 \
  --region=$REGION \
  --advertisement-mode=CUSTOM \
  --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR

gcloud container clusters update $GKE_CLUSTER_NAME \
    --enable-master-authorized-networks \
    --region=$REGION \
    --master-authorized-networks="$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX"

gcloud projects add-iam-policy-binding $VPC_HOST_PROJECT \
    --member=serviceAccount:$VPC_HOST_PROJECT_NUMBER@cloudbuild.gserviceaccount.com \
    --role=roles/container.developer

# TODO: add verification test here