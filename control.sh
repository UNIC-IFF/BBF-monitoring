#!/bin/bash

DEFAULT_ENVFILE="$(dirname $0)/defaults.env"
ENVFILE=${ENVFILE:-"$DEFAULT_ENVFILE"}
### Define or load default variables
source $ENVFILE
###
WORKING_DIR=${WORKING_DIR:-"$(dirname $0)"}
MONITORING_SERVICES_DOCKER_COMPOSE_FILE=monitoring_compose.yml
TESTNET_NAME=${TESTNET_NAME:-"benchmarking-fw-net"}
INFLUXDB_VOL_NAME=${INFLUXDB_VOL_NAME:-"testnet_influxdb_data"}
GF_DATA_VOL_NAME=${GF_DATA_VOL_NAME:-"testnet_grafana_data"}
PROM_DATA_VOL_NAME=${PROM_DATA_VOL_NAME:-"testnet_prometheus_data"}

### Source scripts under scripts directory
#. $(dirname $0)/scripts/helper_functions.sh
###


USAGE="$(basename $0) is the main control script for the monitoring stack.
Usage : $(basename $0) <action> <arguments>

Actions:
  start
       Starts the monitoring stack 
  configure --enable-ELK|-elk  --reverse-proxy
       configures the monitoring stack with ELK or/reverse proxy options enabled
  stop
       Stops the monitoring stack
  clean
       Cleans up the configuration directories
  status
       Prints the status of the network
        "

function help()
{
  echo "$USAGE"
}

function generate_network_configs()
{
  nvals=$1
  echo "Generating monitoring stack  configuration..."
  #enable debug
  #set -x

  running_testnet=$(docker network ls --filter=name=${TESTNET_NAME} --format "{{.Name}}" | head -n 1)

  if [[ -n $running_testnet ]] ; then
    echo "Found a running ${TESTNET_NAME}. Attaching the monitoring services containers to it."
  else
    echo "The ${TESTNET_NAME} docker network couldn't be found!"
    docker network create ${TESTNET_NAME}
    return 1;
  fi;

  #creating docker volumes if they are not existed

  existedvol=$(docker volume ls --filter=name=$INFLUXDB_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring InfluxDB, $existedvol. Attaching it to the monitoring influxdb."
  else
    echo "The $INFLUXDB_VOL_NAME docker volume not found! Creating one..."
    docker volume create $INFLUXDB_VOL_NAME
  fi;


  existedvol=$(docker volume ls --filter=name=$GF_DATA_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring Grafana dashboard, $existedvol. Attaching it to the Grafana container."
  else
    echo "The $GF_DATA_VOL_NAME docker volume not found! Creating one..."
    docker volume create $GF_DATA_VOL_NAME
  fi;

  existedvol=$(docker volume ls --filter=name=$PROM_DATA_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring Prometheus service, $existedvol. Attaching it to the Prometheus container."
  else
    echo "The $PROM_DATA_VOL_NAME docker volume not found! Creating one..."
    docker volume create $PROM_DATA_VOL_NAME
    docker run --rm -v $PROM_DATA_VOL_NAME:/prom alpine sh -c 'chown -R 65534:65534 /prom'
  fi;
  echo "  done!"
}

function start_network()
{
  nvals=$1
  echo "Starting network with $nvals validators..."
  # TESTNET_NAME=$TESTNET_NAME docker-compose -f docker-compose-testnet.yml up -d
  running_testnet=$(docker network ls --filter=name=${TESTNET_NAME} --format "{{.Name}}" | head -n 1)

  TESTNET=${running_testnet} \
  GF_DATA_VOL_NAME=$GF_DATA_VOL_NAME \
  INFLUXDB_VOL_NAME=$INFLUXDB_VOL_NAME \
  PROM_DATA_VOL_NAME=$PROM_DATA_VOL_NAME \
    docker-compose -f ${WORKING_DIR}/${MONITORING_SERVICES_DOCKER_COMPOSE_FILE} up -d

  #create prometheus as a data source in grafana container
  #chmod +x ./monitoring_system/create-datasource.sh
  $(dirname $0)/scripts/create-datasource.sh
 
  echo "  network started!"
}

function stop_network()
{
  echo "Stopping network..."
  running_testnet=$(docker network ls --filter=name=${TESTNET_NAME} --format "{{.Name}}" | head -n 1)

  TESTNET=${running_testnet} \
  GF_DATA_VOL_NAME=$GF_DATA_VOL_NAME \
  INFLUXDB_VOL_NAME=$INFLUXDB_VOL_NAME \
  PROM_DATA_VOL_NAME=$PROM_DATA_VOL_NAME \
    docker-compose -f ${WORKING_DIR}/${MONITORING_SERVICES_DOCKER_COMPOSE_FILE} down
  echo "  stopped!"
}

function print_status()
{
  echo "Printing status of the  network..."

  running_testnet=$(docker network ls --filter=name=${TESTNET_NAME} --format "{{.Name}}" | head -n 1)

  TESTNET=${running_testnet} \
  GF_DATA_VOL_NAME=$GF_DATA_VOL_NAME \
  INFLUXDB_VOL_NAME=$INFLUXDB_VOL_NAME \
  PROM_DATA_VOL_NAME=$PROM_DATA_VOL_NAME \
    docker-compose -f ${WORKING_DIR}/${MONITORING_SERVICES_DOCKER_COMPOSE_FILE} ps

  echo "  Finished!"
}

function do_cleanup()
{
  echo "Cleaning up network configuration..."
  # rm -rf ${DEPLOYMENT_DIR}/*
  existedvol=$(docker volume ls --filter=name=$INFLUXDB_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring InfluxDB, $existedvol. Attaching it to the monitoring influxdb."
    docker volume rm $INFLUXDB_VOL_NAME
  else
    echo "The $INFLUXDB_VOL_NAME docker volume not found!"
  fi;


  existedvol=$(docker volume ls --filter=name=$GF_DATA_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring Grafana dashboard, $existedvol. Attaching it to the Grafana container."
    docker volume rm $GF_DATA_VOL_NAME
  else
    echo "The $GF_DATA_VOL_NAME docker volume not found!"
  fi;

  existedvol=$(docker volume ls --filter=name=$PROM_DATA_VOL_NAME --format "{{.Name}}" | head -n 1)
  if [[ -n $existedvol ]] ; then
    echo "Found an existed docker volume for monitoring Prometheus service, $existedvol. Attaching it to the Prometheus container."
    docker volume rm $PROM_DATA_VOL_NAME
  else
    echo "The $PROM_DATA_VOL_NAME docker volume not found! "
  fi;
  echo "  clean up finished!"
}


ARGS="$@"

if [ $# -lt 1 ]
then
  #echo "No args"
  help
  exit 1
fi

while [ "$1" != "" ]; do
  case $1 in
    "start" ) shift
      start_network
      exit
      ;;
    "configure" ) shift
      while [ "$1" != "" ]; do
        case $1 in 
             -n|--val-num ) shift
               VAL_NUM=$1
               ;;
        esac
        shift
      done
      generate_network_configs $VAL_NUM
      exit
      ;;
    "stop" ) shift
      stop_network
      exit
      ;;
    "status" ) shift
      print_status
      exit
      ;;
    "clean" ) shift
      do_cleanup
      exit
      ;;
  esac
  shift
done
