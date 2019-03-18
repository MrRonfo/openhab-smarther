#!/bin/bash

temp_dir=$OPENHAB_CONF/scripts/smarther/temp

devapi_url="https://api.developer.legrand.com/smarther/v2.0"
thermo_url="$devapi_url/chronothermostat/thermoregulation/addressLocation"
notify_url="<URL of your Cloud 2 Cloud notifications endpoint>/smarther-c2c.php"

log_level="INFO"

function sendHttpGetRequest() {
  log DEBUG "Command: $1 Url: $2"
  local __rsp_data=$(curl -w "\n%{http_code}" -s -X GET "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $key" -H "Authorization: $ocm")
  log INFO "Command: $1 Received: $__rsp_data"
  echo "$__rsp_data"
}

function sendHttpPostRequest() {
  log DEBUG "Command: $1 Url: $2 Body: $3"
  local __rsp_data=$(curl -w "\n%{http_code}" -s -X POST "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $key" -H "Authorization: $ocm" --data-ascii "$3")
  log INFO "Command: $1 Received: $__rsp_data"
  echo "$__rsp_data"
}

function sendHttpDeleteRequest() {
  log DEBUG "Command: $1 Url: $2"
  local __rsp_data=$(curl -w "\n%{http_code}" -s -X DELETE "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $key" -H "Authorization: $ocm")
  log INFO "Command: $1 Received: $__rsp_data"
  echo "$__rsp_data"
}

function getHttpRspCode() {
  echo "${1##*$'\n'}"
}

function getHttpRspBody() {
  echo "$1" | sed '$ d'
}

function getHttpErrorMsg() {
  local __rsp_errm=$(echo "$2" | sed "$ d" | jq -r '.message')
  echo "\"errormsg\":\"($1) $__rsp_errm\""
}

function log() {
  if [ "$log_level" = "DEBUG" ] || [ "$1" = "INFO" ]; then
    echo $(printf "[%-5s][%(%d/%m/%Y %H:%M:%S)T]" $1) $2 >> $OPENHAB_CONF/scripts/smarther/log/smarther.log
  fi
}

client_id="<your client id>"
client_secret="<your client secret password>"
plant_id="<the plant id whose thermostat you want to control>"
module_id="<the module id of the thermostat you want to control>"
grant_type="refresh_token"
refresh_token=""

timestamp_now=`date +%s`
timestamp_now_2_date=`date -d "@$timestamp_now"`

# Access token is valid for 1 hour.
# Now checking whether a new access token must be required or not.
timestamp_expiry_access_token=`less $temp_dir/refresh.json | jq -r .expires_on`
timestamp_expiry_access_token_2_date=`date -d "@$timestamp_expiry_access_token"`

access_token=""

if [ $timestamp_expiry_access_token -gt $timestamp_now ]; then
  # Access token is valid, no further token request is performed.
  log DEBUG "Access Token still valid (expires on: $timestamp_expiry_access_token_2_date)"
  access_token=`less $temp_dir/refresh.json | jq -r .access_token`

else
  # Access token has expired, a new token must be requested.
  log DEBUG "Access Token not valid (expired on: $timestamp_expiry_access_token_2_date)"
  refresh_token=`less $temp_dir/refresh.json | jq -r .refresh_token`

  log DEBUG "Send request for new access token"
  curl -s -X POST -d "client_id=$client_id&client_secret=$client_secret&grant_type=$grant_type&refresh_token=$refresh_token" https://partners-login.eliotbylegrand.com/token > $temp_dir/refresh.tmp
  sleep 5

  if $(less $temp_dir/refresh.tmp | jq 'has("error")'); then
    rsp_errm=$(less $temp_dir/refresh.tmp | jq '.error_message')
    log DEBUG "Request failed with error: $rsp_errm"
    echo "{\"rsptype\":\"$1\",\"rspcode\":500,\"errormsg\":\"$rsp_json\"}"
    exit 1
  fi

  less $temp_dir/refresh.tmp | jq '.' | more > $temp_dir/refresh.json
  access_token=`less $temp_dir/refresh.json | jq -r .access_token`

  timestamp_expiry_access_token=`less $temp_dir/refresh.json | jq -r .expires_on`
  timestamp_expiry_access_token_2_date=`date -d "@$timestamp_expiry_access_token"`

  log DEBUG "Done. Access Token new expiry date = $timestamp_expiry_access_token_2_date"
fi

key="<primary key of your subscription>"
ocm="Bearer $access_token"

rsp_code=0
rsp_json=""
case $1 in
  get_measures)
    # Operation used to retrieve the measured temperature and humidity detected by a chronothermostat.
    rsp_data=$(sendHttpGetRequest $1 "$thermo_url/plants/$plant_id/modules/parameter/id/value/$module_id/measures")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 200 ]; then
      rsp_body=$(getHttpRspBody "$rsp_data")
      rsp_temp=$(echo "$rsp_body" | jq '.thermometer.measures[0].value | tonumber')
      rsp_humi=$(echo "$rsp_body" | jq '.hygrometer.measures[0].value | tonumber')
      rsp_json="\"temperature\":$rsp_temp,\"humidity\":$rsp_humi"
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  get_status)
    # Operation used to retrieve the complete status of a chronothermostat.
    rsp_data=$(sendHttpGetRequest $1 "$thermo_url/plants/$plant_id/modules/parameter/id/value/$module_id")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 200 ]; then
      rsp_body=$(getHttpRspBody "$rsp_data")
      rsp_func=$(echo "$rsp_body" | jq '.chronothermostats[0].function')
      rsp_mode=$(echo "$rsp_body" | jq '.chronothermostats[0].mode')
      rsp_setp=$(echo "$rsp_body" | jq '.chronothermostats[0].setPoint.value | tonumber')
      rsp_prog=$(echo "$rsp_body" | jq '.chronothermostats[0].programs[0].number')
      rsp_time=$(echo "$rsp_body" | jq 'if .chronothermostats[0].activationTime != null then .chronothermostats[0].activationTime else "forever" end')
      rsp_frmt=$(echo "$rsp_body" | jq '.chronothermostats[0].temperatureFormat')
      rsp_load=$(echo "$rsp_body" | jq '.chronothermostats[0].loadState')
      rsp_temp=$(echo "$rsp_body" | jq '.chronothermostats[0].thermometer.measures[0].value | tonumber')
      rsp_humi=$(echo "$rsp_body" | jq '.chronothermostats[0].hygrometer.measures[0].value | tonumber')
      rsp_json="\"function\":$rsp_func,\"mode\":$rsp_mode,\"setpoint\":$rsp_setp,\"program\":$rsp_prog,\"time\":$rsp_time,\"tempformat\":$rsp_frmt,\"status\":$rsp_load,\"temperature\":$rsp_temp,\"humidity\":$rsp_humi"
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  get_programs)
    # Operation used to retrieve the list of programs managed by a chronothermostat.
    rsp_data=$(sendHttpGetRequest $1 "$thermo_url/plants/$plant_id/modules/parameter/id/value/$module_id/programlist")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 200 ]; then
      rsp_body=$(getHttpRspBody "$rsp_data")
      rsp_prog=$(echo "$rsp_body" | jq -c '.chronothermostats[0].programs')
      rsp_json="\"programs\":$rsp_prog"
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  get_subscriptions)
    # Operation used to get subscriptions of a user to get Cloud2Cloud notifications of a plant.
    rsp_data=$(sendHttpGetRequest $1 "$devapi_url/subscription")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 200 ]; then
      rsp_body=$(getHttpRspBody "$rsp_data")
      rsp_json="\"subscriptions\":$rsp_body"
    elif [ $rsp_code -eq 204 ]; then
      rsp_json="\"errormsg\":\"($1) No subscription associated with this user\""
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  set_thermo)
    # Operation used to set the status of a chronothermostat.
    # Input arguments: $2 = Mode, $3 = Program, $4 = SetPoint, $5 = Timer
    data_ascii=""
    case $2 in
      automatic)
        data_ascii="{\"function\":\"heating\",\"mode\":\"automatic\",\"programs\":[{\"number\":$3}]}"
        ;;
      manual)
        if [ "$5" = "off" ]; then
          data_ascii="{\"function\":\"heating\",\"mode\":\"manual\",\"setPoint\":{\"value\":$4,\"unit\":\"C\"}}"
        else
          data_ascii="{\"function\":\"heating\",\"mode\":\"manual\",\"setPoint\":{\"value\":$4,\"unit\":\"C\"},\"activationTime\":\"$5\"}"
        fi
        ;;
      protection)
        data_ascii="{\"function\":\"heating\",\"mode\":\"protection\"}"
        ;;
      boost)
        data_ascii="{\"function\":\"heating\",\"mode\":\"boost\",\"activationTime\":\"$5\"}"
        ;;
      off)
        data_ascii="{\"function\":\"heating\",\"mode\":\"off\"}"
        ;;
    esac

    if [ -n "$data_ascii" ]; then
      rsp_data=$(sendHttpPostRequest $1 "$thermo_url/plants/$plant_id/modules/parameter/id/value/$module_id" "$data_ascii")
      rsp_code=$(getHttpRspCode "$rsp_data")

      if [ $rsp_code -eq 200 ]; then
        # Retrieving chronothermostat updated status
        rsp_data=$(sendHttpGetRequest $1 "$thermo_url/plants/$plant_id/modules/parameter/id/value/$module_id")
        rsp_code=$(getHttpRspCode "$rsp_data")

        if [ $rsp_code -eq 200 ]; then
          rsp_body=$(getHttpRspBody "$rsp_data")
          rsp_func=$(echo "$rsp_body" | jq '.chronothermostats[0].function')
          rsp_mode=$(echo "$rsp_body" | jq '.chronothermostats[0].mode')
          rsp_setp=$(echo "$rsp_body" | jq '.chronothermostats[0].setPoint.value | tonumber')
          rsp_prog=$(echo "$rsp_body" | jq '.chronothermostats[0].programs[0].number')
          rsp_time=$(echo "$rsp_body" | jq 'if .chronothermostats[0].activationTime != null then .chronothermostats[0].activationTime else "forever" end')
          rsp_frmt=$(echo "$rsp_body" | jq '.chronothermostats[0].temperatureFormat')
          rsp_load=$(echo "$rsp_body" | jq '.chronothermostats[0].loadState')
          rsp_temp=$(echo "$rsp_body" | jq '.chronothermostats[0].thermometer.measures[0].value | tonumber')
          rsp_humi=$(echo "$rsp_body" | jq '.chronothermostats[0].hygrometer.measures[0].value | tonumber')

          rsp_json="\"function\":$rsp_func,\"mode\":$rsp_mode,\"setpoint\":$rsp_setp,\"program\":$rsp_prog,\"time\":$rsp_time,\"tempformat\":$rsp_frmt,\"status\":$rsp_load,\"temperature\":$rsp_temp,\"humidity\":$rsp_humi"
        else
          rsp_json=$(getHttpErrorMsg "$1, status" "$rsp_data")
        fi
      else
        rsp_json=$(getHttpErrorMsg "$1, thermo" "$rsp_data")
      fi
    else
      rsp_code=400
      rsp_json="\"errormsg\":\"Mode ($2) is not a valid mode\""
    fi
    ;;

  set_subscriptions)
    # Operation used to subscribe a user to get Cloud2Cloud notifications of a plant.
    rsp_data=$(sendHttpPostRequest $1 "$devapi_url/plants/$plant_id/subscription" "{\"EndPointUrl\":\"$notify_url\"}")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 201 ]; then
      rsp_body=$(getHttpRspBody "$rsp_data")
      rsp_json="\"subscriptions\":$rsp_body"
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  delete_subscriptions)
    # Operation used to delete the subscription of a user to get Cloud2Cloud notifications of a plant.
    rsp_data=$(sendHttpDeleteRequest $1 "$devapi_url/plants/$plant_id/subscription/$2")
    rsp_code=$(getHttpRspCode "$rsp_data")

    if [ $rsp_code -eq 200 ]; then
      rsp_json="\"done\":\"OK\""
    else
      rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
    fi
    ;;

  test_get_measures)
    rsp_code=200
    rsp_json="\"temperature\":18.3,\"humidity\":70.7"
    ;;

  test_get_status)
    rsp_code=200
    rsp_json="\"function\":\"HEATING\",\"mode\":\"MANUAL\",\"setpoint\":20,\"program\":0,\"time\":\"2019-02-17T23:30:00\",\"tempformat\":\"C\",\"status\":\"ACTIVE\",\"temperature\":18.3,\"humidity\":70.7"
    ;;

  test_get_programs)
    rsp_code=200
    rsp_json="\"programs\":[{\"number\":0,\"name\":\"0\"},{\"number\":1,\"name\":\"My program\"}]"
    ;;

  test_get_notifications)
    rsp_code=200
    rsp_json="\"programs\":[{\"number\":0,\"name\":\"0\"},{\"number\":1,\"name\":\"My program\"}]"
    ;;

  test_set_thermo)
    rsp_code=200
    rsp_json="\"function\":\"HEATING\",\"mode\":\"MANUAL\",\"setpoint\":20,\"program\":0,\"time\":\"2019-02-17T23:30:00\",\"tempformat\":\"C\",\"status\":\"ACTIVE\",\"temperature\":18.4,\"humidity\":70.5"
    ;;

  *)
    rsp_code=400
    rsp_json="\"errormsg\":\"Command ($1) is not a valid command\""
    ;;

esac

rsp_json="{\"rsptype\":\"$1\",\"rspcode\":$rsp_code,$rsp_json}"

log INFO "Command: $1 Response: $rsp_json"
echo "$rsp_json"
