#!/bin/bash

function cluster_connect() {
  if [ -z ${AGENT_NAME+x} ] || [ -z ${AGENT_PROJECT_PATH+x} ]; then
    echo "No AGENT_NAME or AGENT_PROJECT_PATH set, using the default"
  else
    kubectl config get-contexts
    kubectl config use-context ${AGENT_PROJECT_PATH}:${AGENT_NAME}
  fi
}

function vcluster_create() {
  vcluster create ${VCLUSTER_NAME} \
    --upgrade \
    --namespace=${VCLUSTER_NAME} \
    --kubernetes-version=${VCLUSTER_K8S_VERSION} \
    --connect=false \
    --update-current=false
}

function vcluster_run() {
  vcluster connect ${VCLUSTER_NAME} -- $@
}

function vcluster_helm_deploy() {
  helm dependency update

  vcluster_run helm upgrade --install \
    gitlab \
    --wait --timeout 600s \
    -f ./scripts/ci/vcluster_helm_values.yaml \
    .
}

function vcluster_helm_rollout_status() {
  vcluster_run kubectl rollout status deployment/gitlab-webservice-default --timeout=300s
}

function vcluster_delete() {
  vcluster delete ${VCLUSTER_NAME}
}

function vcluster_info() {
  echo "To connect to the virtual cluster:"
  echo "1. Connect to host cluster via kubectl: ${AGENT_NAME}"
  echo "2. Connect to virtual cluster: vcluster connect ${VCLUSTER_NAME}"
  echo "3. Open a separate terminal window and run your kubectl and helm commands."
}