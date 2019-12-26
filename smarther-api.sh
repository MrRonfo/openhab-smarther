#!/bin/bash

#-------------------------------------------------------------------------------
# BEGIN -- Configuration Section
#--------------------------------
# API subscription key
subscription_key="yourSubscriptionKey"
# Application credentials
client_id="yourClientId"
client_secret="yourClientSecret"
redirect_uri="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-auth.php"
# Chronothermostat topology
plant_id="thePlantIdOfYourHome"
module_id="theModuleIdOfYourThermostat"
# Cloud2Cloud notification callback URL
notify_url="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-c2c.php"
# Log level
log_level="INFO"
#--------------------------------
# END -- Configuration Section
#-------------------------------------------------------------------------------

oauth2_url="https://partners-login.eliotbylegrand.com/authorize"
token_url="https://partners-login.eliotbylegrand.com/token"
devapi_url="https://api.developer.legrand.com/smarther/v2.0"
thermo_url="$devapi_url/chronothermostat/thermoregulation/addressLocation"
data_dir=$OPENHAB_CONF/scripts/smarther/data

#-------------------------------------------------------------------------------
# Send an http GET request
# ($1 = log command, $2 = destination url)
function sendHttpGetRequest() {
    log DEBUG "Command: $1 Url: $2"
    local __rsp_data=$(curl -w "\n%{http_code}" -s -X GET "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $subscription_key" -H "Authorization: $ocm")
    log INFO "Command: $1 Received: $__rsp_data"
    echo "$__rsp_data"
}

#-------------------------------------------------------------------------------
# Send an http POST request
# ($1 = log command, $2 = destination url, $3 = request body)
function sendHttpPostRequest() {
    log DEBUG "Command: $1 Url: $2 Body: $3"
    local __rsp_data=$(curl -w "\n%{http_code}" -s -X POST "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $subscription_key" -H "Authorization: $ocm" --data-ascii "$3")
    log INFO "Command: $1 Received: $__rsp_data"
    echo "$__rsp_data"
}

#-------------------------------------------------------------------------------
# Send an http DELETE request
# ($1 = log command, $2 = destination url)
function sendHttpDeleteRequest() {
    log DEBUG "Command: $1 Url: $2"
    local __rsp_data=$(curl -w "\n%{http_code}" -s -X DELETE "$2" -H "Content-Type: application/json" -H "Ocp-Apim-Subscription-Key: $subscription_key" -H "Authorization: $ocm")
    log INFO "Command: $1 Received: $__rsp_data"
    echo "$__rsp_data"
}

#-------------------------------------------------------------------------------
# Extract the http response code from response data
# ($1 = response data)
function getHttpRspCode() {
    echo "${1##*$'\n'}"
}

#-------------------------------------------------------------------------------
# Extract the http response body from response data
# ($1 = response data)
function getHttpRspBody() {
    echo "$1" | sed '$ d'
}

#-------------------------------------------------------------------------------
# Construct an error message from http response data
# ($1 = log command, $2 = response data)
function getHttpErrorMsg() {
    local __rsp_errm=$(echo "$2" | sed "$ d" | jq -r '.message')
    echo "\"errormsg\":\"($1) $__rsp_errm\""
}

#-------------------------------------------------------------------------------
# Construct the OAuth2 end-point Url to be called from browser
function getOAuth2CallUrl() {
    local __oauth2_state=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    echo "$oauth2_url?client_id=$client_id&response_type=code&redirect_uri=$redirect_uri&state=$__oauth2_state"
}

#-------------------------------------------------------------------------------
# Write a message in the application log
# ($1 = log command, $2 = log message)
function log() {
    if [ "$log_level" = "DEBUG" ] || [ "$1" = "INFO" ]; then
        echo $(printf "[%-5s][%(%d/%m/%Y %H:%M:%S)T]" $1) $2 >> $OPENHAB_CONF/scripts/smarther/log/smarther.log
    fi
}

timestamp_now=$(date +%s)

# Access token is valid for 1 hour
access_token=""

# Getting access token expiry string from refresh token file
access_token_expiry_string=""
if [ -f $data_dir/refresh.json ]; then
    access_token_expiry_string=$(less $data_dir/refresh.json | jq -r .expires_on)
fi

if [ -z "$access_token_expiry_string" ]; then
    #---------------------------------------------------------------------------
    # Refresh token file is missing, restart the authorization process
    #---------------------------------------------------------------------------
    log DEBUG "Access token expiry tstamp is missing or invalid"

    # Getting OAuth2 code from authorization file
    oauth2_code=""
    if [ -f $data_dir/authorization.json ]; then
        oauth2_code=$(less $data_dir/authorization.json | jq -r .oauth2_code)
    fi

    if [ -z "$oauth2_code" ]; then
        # OAuth2 code is missing or invalid: quit
        rsp_errm="OAuth2 code is missing or invalid. To restore the authentication flow call the following Url from a browser: $(getOAuth2CallUrl)"
        log DEBUG "Authorization.json: $rsp_errm"
        echo "{\"rsptype\":\"$1\",\"rspcode\":500,\"errormsg\":\"$rsp_errm\"}"
        exit 1
    fi

    log DEBUG "OAuth2 code: $oauth2_code"

    # Calling the token end-point to get a new access token
    log DEBUG "Sending request to get new access token"
    rsp_data=$(curl -w "\n%{http_code}" -s -X POST -d "client_id=$client_id&client_secret=$client_secret&grant_type=authorization_code&code=$oauth2_code" $token_url)

    rsp_code=$(getHttpRspCode "$rsp_data")
    rsp_body=$(getHttpRspBody "$rsp_data")
    if [ $rsp_code -ne 200 ]; then
        # Call failed: http response has errors, quit
        rsp_errm="Error getting new access token from server"
        if [ $(echo $rsp_body | jq 'has("error")') ]; then
            if [ $(echo $rsp_body | jq '.error_description | contains ("AADB2C90080")') ]; then
                rsp_errm="OAuth2 code has expired. To restore the authentication flow call the following Url from a browser: $(getOAuth2CallUrl)"
            else
                rsp_errm=$(echo $rsp_body | jq -r '.error_description | gsub("\\r";"") | gsub("\\n";" ")')
            fi
        fi
        log DEBUG "Request failed with error: $rsp_errm"
        echo "{\"rsptype\":\"$1\",\"rspcode\":$rsp_code,\"errormsg\":\"$rsp_errm\"}"
        exit 1
    fi

    # Copying response into formatted refresh token file
    echo $rsp_body | jq '.' | more > $data_dir/refresh.json
    access_token=$(less $data_dir/refresh.json | jq -r .access_token)

    # Getting user:group:permissions information on this script
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"
    user_group=$(stat -c "%U:%G" $script_dir/smarther-api.sh)
    # Making sure the refresh token file is owned by same user:group as this script
    sudo chown $user_group $data_dir/refresh.json
    # Making sure that write permission on refresh token file is granted to group members as well
    sudo chmod 664 $data_dir/refresh.json

    # Logging access token expiry timestamp
    access_token_expiry_string=$(less $data_dir/refresh.json | jq -r .expires_on)
    access_token_expiry_tstamp=$(date -d "@$access_token_expiry_string")

    log DEBUG "Done. Access Token new expiry date = $access_token_expiry_tstamp"

elif [ $access_token_expiry_string -le $timestamp_now ]; then
    #---------------------------------------------------------------------------
    # Refresh token file is present, access token is present but has expired
    #---------------------------------------------------------------------------
    access_token_expiry_tstamp=$(date -d "@$access_token_expiry_string")
    log DEBUG "Access token has expired on $access_token_expiry_tstamp"

    # Getting refresh token from refresh token file
    refresh_token=$(less $data_dir/refresh.json | jq -r .refresh_token)

    # Calling the refresh token flow to get a new access token
    log DEBUG "Sending request to refresh the access token"
    rsp_data=$(curl -w "\n%{http_code}" -s -X POST -d "client_id=$client_id&client_secret=$client_secret&grant_type=refresh_token&refresh_token=$refresh_token" $token_url)

    rsp_code=$(getHttpRspCode "$rsp_data")
    rsp_body=$(getHttpRspBody "$rsp_data")
    if [ $rsp_code -ne 200 ]; then
        # Call failed: http response has errors, quit
        rsp_errm="Error refreshing the access token from server"
        if [ $(echo $rsp_body | jq 'has("error")') ]; then
            rsp_errm=$(echo $rsp_body | jq -r '.error_description | gsub("\\r";"") | gsub("\\n";" ")')
        fi
        log DEBUG "Request failed with error: $rsp_errm"
        echo "{\"rsptype\":\"$1\",\"rspcode\":$rsp_code,\"errormsg\":\"$rsp_errm\"}"
        exit 1
    fi

    # Copying response into formatted refresh token file
    echo $rsp_body | jq '.' | more > $data_dir/refresh.json
    access_token=$(less $data_dir/refresh.json | jq -r .access_token)

    # Logging access token expiry timestamp
    access_token_expiry_string=$(less $data_dir/refresh.json | jq -r .expires_on)
    access_token_expiry_tstamp=$(date -d "@$access_token_expiry_string")

    log DEBUG "Done. Access token new expiry date = $access_token_expiry_tstamp"

else
    #---------------------------------------------------------------------------
    # Refresh token file is present, access token is present and is still valid
    #---------------------------------------------------------------------------
    access_token_expiry_tstamp=$(date -d "@$access_token_expiry_string")
    log DEBUG "Access token is still valid (will expire on: $access_token_expiry_tstamp)"

    # Getting access token from refresh token file
    access_token=$(less $data_dir/refresh.json | jq -r .access_token)
fi

ocm="Bearer $access_token"

rsp_code=0
rsp_json=""
case $1 in
    get_measures)
        # Operation used to retrieve the measured temperature and humidity detected by a chronothermostat
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
        # Operation used to retrieve the complete status of a chronothermostat
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
        # Operation used to retrieve the list of programs managed by a chronothermostat
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
        # Operation used to get subscriptions of a user to get Cloud2Cloud notifications of a plant
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
                if [ "$5" = "forever" ]; then
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

    set_subscription)
        # Operation used to subscribe a user to get Cloud2Cloud notifications of a plant
        rsp_data=$(sendHttpPostRequest $1 "$devapi_url/plants/$plant_id/subscription" "{\"EndPointUrl\":\"$notify_url\"}")
        rsp_code=$(getHttpRspCode "$rsp_data")

        if [ $rsp_code -eq 201 ]; then
            rsp_body=$(getHttpRspBody "$rsp_data")
            rsp_json="\"subscriptions\":$rsp_body"
        else
            rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
        fi
    ;;

    delete_subscription)
        # Operation used to delete the subscription of a user to get Cloud2Cloud notifications of a plant
        rsp_data=$(sendHttpDeleteRequest $1 "$devapi_url/plants/$plant_id/subscription/$2")
        rsp_code=$(getHttpRspCode "$rsp_data")

        if [ $rsp_code -eq 200 ]; then
            rsp_json="\"done\":\"OK\""
        else
            rsp_json=$(getHttpErrorMsg $1 "$rsp_data")
        fi
    ;;

    *)
        rsp_code=400
        rsp_json="\"errormsg\":\"Command ($1) is not a valid command\""
    ;;

esac

rsp_json="{\"rsptype\":\"$1\",\"rspcode\":$rsp_code,$rsp_json}"

log INFO "Command: $1 Response: $rsp_json"
echo "$rsp_json"
