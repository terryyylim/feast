#!/usr/bin/env bash
echo "Preparing environment variables..."

set -e
set -o pipefail

test -z ${GOOGLE_APPLICATIONS_CREDENTIALS} && GOOGLE_APPLICATION_CREDENTIALS="/etc/service-account/service-account.json"
test -z ${GCLOUD_PROJECT} && GCLOUD_PROJECT="kf-feast"
test -z ${TEMP_BUCKET} && TEMP_BUCKET="feast-templocation-kf-feast"
test -z ${JOBS_STAGING_LOCATION} && JOBS_STAGING_LOCATION="gs://${TEMP_BUCKET}/staging-location"
test -z ${GCLOUD_REGION} && GCLOUD_REGION="asia-east1"
test -z ${GCLOUD_NETWORK} && GCLOUD_NETWORK="default"
test -z ${GCLOUD_SUBNET} && GCLOUD_SUBNET="default"
test -z ${K8_CLUSTER_NAME} && K8_CLUSTER_NAME="kf-feast-e2e-dataflow"
test -z ${HELM_RELEASE_NAME} && HELM_RELEASE_NAME="kf-feast-release"

echo "
This script will run end-to-end tests for Feast Core and Batch Serving using DataflowRunner.

1. Install gcloud SDK.
2. Stage infrastructure (GKE and IP addresses) for running test. 
3. Install Redis as the job store for Feast Batch Serving, Postgres for persisting Feast metadata,
   Kafka and Zookeeper as the Source in Feast via Feast Helm chart.
4. Install Python 3.7.4, Feast Python SDK and run end-to-end tests from
   tests/e2e via pytest.
5. Tear down infrastructure.
"

# Updates and installations
apt-get -qq update
apt-get -y install wget netcat kafkacat build-essential gettext-base
sudo snap install helm --classic

ORIGINAL_DIR=$(pwd)
echo $ORIGINAL_DIR

echo "
============================================================
Installing gcloud SDK
============================================================
"
if [[ ! $(command -v gsutil) ]]; then
  CURRENT_DIR=$(dirname "$BASH_SOURCE")
  . "${CURRENT_DIR}"/install-google-cloud-sdk.sh
fi

export GOOGLE_APPLICATION_CREDENTIALS
gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}

gcloud config set project ${GCLOUD_PROJECT}
gcloud config set compute/region ${GCLOUD_REGION}
gcloud config list

echo "
============================================================
Creating temp BQ table for Feast Serving
============================================================
"
DATASET_NAME=feast_e2e_$(date +%s)

bq --location=US --project_id=${GCLOUD_PROJECT} mk \
  --dataset \
  --default_table_expiration 86400 \
  ${GCLOUD_PROJECT}:${DATASET_NAME}

echo "
============================================================
Check and generate valid k8s cluster name
============================================================
"
count=0
for cluster_name in $(gcloud container clusters list --format "list(name)")
do
  if [[ $cluster_name == "feast-e2e-dataflow"* ]]; then
    count += 1
  fi
done
temp="$K8_CLUSTER_NAME-$count"
export K8_CLUSTER_NAME=$temp
echo "Cluster name is $K8_CLUSTER_NAME"

echo "
============================================================
Reserving IP addresses for Feast dependencies
============================================================
"
feast_kafka_1_ip="feast-kafka-$((count*3 + 1))"
feast_kafka_2_ip="feast-kafka-$((count*3 + 2))"
feast_kafka_3_ip="feast-kafka-$((count*3 + 3))"
feast_redis_ip="feast-redis-$((count + 1))"
feast_statsd_ip="feast-statsd-$((count + 1))"
gcloud compute addresses create \
  $feast_kafka_1_ip $feast_kafka_2_ip $feast_kafka_3_ip $feast_redis_ip $feast_statsd_ip \
  --region ${GCLOUD_REGION} --subnet ${GCLOUD_SUBNET}
for ip_addr_name in $feast_kafka_1_ip $feast_kafka_2_ip $feast_kafka_3_ip $feast_redis_ip $feast_statsd_ip
do
  export "$(echo ${ip_addr_name} | tr '-' '_')=$(gcloud compute addresses describe ${ip_addr_name} --region=asia-east1 --format "value(address)")"
done

echo "
============================================================
Creating GKE nodepool for Feast e2e test with DataflowRunner
============================================================
"
gcloud container clusters create ${K8_CLUSTER_NAME} --region ${GCLOUD_REGION} \
    --enable-cloud-logging \
    --enable-cloud-monitoring \
    --network ${GCLOUD_NETWORK} \
    --subnetwork ${GCLOUD_SUBNET} \
    --machine-type n1-standard-2
sleep 120

echo "
============================================================
Create feast-gcp-service-account Secret in GKE nodepool
============================================================
"
kubectl create secret generic feast-gcp-service-account --from-file=${GOOGLE_APPLICATIONS_CREDENTIALS}

echo "
============================================================
Helm install Feast and its dependencies
============================================================
"
cd $ORIGINAL_DIR/infra/charts/feast
envsubst < values-dataflow-runner.yaml > values-dataflow-runner-updated.yaml
helm install --wait --timeout 600s --values="values-dataflow-runner-updated.yaml" ${HELM_RELEASE_NAME} .
kubectl get all

echo "
============================================================
Installing Python 3.7 with Miniconda and Feast SDK
============================================================
"
cd $ORIGINAL_DIR
# Install Python 3.7 with Miniconda
wget -q https://repo.continuum.io/miniconda/Miniconda3-4.7.12-Linux-x86_64.sh \
   -O /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p /root/miniconda -f
/root/miniconda/bin/conda init
source ~/.bashrc

# Install Feast Python SDK and test requirements
make compile-protos-python
pip install -qe sdk/python
pip install -qr tests/e2e/requirements.txt

echo "
============================================================
Running end-to-end tests with pytest at 'tests/e2e'
============================================================
"
# Default artifact location setting in Prow jobs
LOGS_ARTIFACT_PATH=/logs/artifacts

cd tests/e2e

set +e
pytest bq-batch-retrieval.py --gcs_path "gs://${TEMP_BUCKET}/" --junitxml=${LOGS_ARTIFACT_PATH}/python-sdk-test-report.xml
TEST_EXIT_CODE=$?

if [[ ${TEST_EXIT_CODE} != 0 ]]; then
  echo "[DEBUG] Printing logs"
  ls -ltrh /var/log/feast*
  cat /var/log/feast-serving-warehouse.log /var/log/feast-core.log

  echo "[DEBUG] Printing Python packages list"
  pip list
fi

cd ${ORIGINAL_DIR}
exit ${TEST_EXIT_CODE}

echo "
============================================================
Cleaning up - To ensure clean slate
============================================================
"
# Remove BQ Dataset
bq rm -r -f ${GCLOUD_PROJECT}:${DATASET_NAME}

# Release IP addresses
for ip_addr_name in $feast_kafka_1_ip $feast_kafka_2_ip $feast_kafka_3_ip $feast_redis_ip $feast_statsd_ip
do
  y | gcloud compute addresses delete ${ip_addr_name} --region=${GCLOUD_REGION}
done

# Delete all k8s services
kubectl delete services --all --cluster ${K8_CLUSTER_NAME}

# Uninstall helm release before clearing PVCs
helm uninstall ${HELM_RELEASE_NAME}
kubectl delete pvc --all --cluster ${K8_CLUSTER_NAME}

# Tear down GKE infrastructure
gcloud container clusters delete --region=${GCLOUD_REGION} ${K8_CLUSTER_NAME}