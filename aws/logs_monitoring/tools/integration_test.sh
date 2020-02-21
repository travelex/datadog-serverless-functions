#!/bin/sh

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Builds Datadogpy layers for lambda functions, using Docker
set -e

if [ -z "$DD_API_KEY" ]; then
    echo 'DD_API_KEY not set. Unable to set up forwarder.'
    exit 1
fi

RUN_ID=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)

CURRENT_VERSION="$(grep -o 'Version: \d\+\.\d\+\.\d\+' template.yaml | cut -d' ' -f2)-staging-${RUN_ID}"

# Make sure we aren't trying to do anything on Datadog's production account. We don't want our
# integration tests to accidentally release a new version of the forwarder
AWS_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
if [ "$AWS_ACCOUNT" = "464622532012" ] ; then
    echo "Detected production credentials. Aborting"
    exit 1
fi

# Run script in this process. This gives us TEMPLATE_URL and FORWARDER_SOURCE_URL env vars
. release.sh datadog-cloudformation-template-staging $CURRENT_VERSION

function param {
    KEY=$1
    VALUE=$2
    echo "{\"ParameterKey\":\"${KEY}\",\"ParameterValue\":${VALUE}}"
}

PARAM_LIST=[$(param DdApiKey \"${DD_API_KEY}\"),$(param DdSite \"datadoghq.com\"),$(param SourceZipUrl \"${FORWARDER_SOURCE_URL}\")]
echo "Setting params ${PARAM_LIST}"

# Create an instance of the stack
STACK_NAME="datadog-forwarder-integration-stack-${RUN_ID}"
echo "Creating stack ${STACK_NAME}"
aws cloudformation create-stack --stack-name $STACK_NAME --template-url $TEMPLATE_URL --capabilities "CAPABILITY_AUTO_EXPAND" "CAPABILITY_IAM" --on-failure "DELETE" \
    --parameters=$PARAM_LIST 

echo "Waiting for stack to complete creation ${STACK_NAME}"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME

echo "Completed stack creation"


