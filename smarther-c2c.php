<?php
require_once __DIR__ . '/../vendor/autoload.php';

use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Monolog\Formatter\LineFormatter;

// Create a log channel
$log = new Logger('Smarther');
$logHandler = new StreamHandler('/var/log/php/smarther-c2c.log', Logger::DEBUG);
$logHandler->setFormatter(new LineFormatter("[%datetime%] %level_name% %message%\n", "d/m/Y H:i:s", false, true));
$log->pushHandler($logHandler);

//------------------------------------------------------------------------------
// BEGIN -- Configuration Section
//--------------------------------

define("REST_API", "http://yourOpenhabServerIP:yourOpenhabServerPort/rest/");

//--------------------------------
// END -- Configuration Section
//------------------------------------------------------------------------------

class ThermostatStatus {
    protected $thHeating;
    protected $thMode;
    protected $thSetPoint;
    protected $thTime;
    protected $thTemperature;
    protected $thHumidity;

    public function __construct($notification) {
        $this->thHeating     = ($notification["loadState"] == "ACTIVE") ? "ON" : "OFF";
        $this->thMode        = $notification["mode"];
        $this->thSetPoint    = $notification["setPoint"]["value"];
        $this->thTemperature = $notification["thermometer"]["measures"][0]["value"];
        $this->thHumidity    = $notification["hygrometer"]["measures"][0]["value"];

        if (isset($notification["activationTime"])) {
            // "activationTime":"2019-02-20T23:30:00Z"
            $tmpActTime  = date_create_from_format('Y-m-d\TH:i:s', $notification["activationTime"]);
            $tmpTomorrow = date_create_from_format('Y-m-d H:i:s', date_format(date_create('tomorrow'), 'Y-m-d').' 00:00:00');
            $tmpDayAfter = date_add($tmpTomorrow, date_interval_create_from_date_string('+1 day'));

            if ($tmpActTime < $tmpTomorrow) {
                $this->thTime = "Today at ".date_format($tmpActTime, 'H:i');
            }
            elseif ($tmpActTime < $tmpDayAfter) {
                $this->thTime = "Tomorrow at ".date_format($tmpActTime, 'H:i');
            }
            else {
                $this->thTime = date_format($tmpActTime, 'd/m/Y \a\t H:i');
            }
        }
        else {
            $this->thTime = "Forever";
        }
    }

    public function getHeating() {
        return $this->thHeating;
    }

    public function getMode() {
        return $this->thMode;
    }

    public function getSetPoint() {
        return $this->thSetPoint;
    }

    public function getTime() {
        return $this->thTime;
    }

    public function getTemperature() {
        return $this->thTemperature;
    }

    public function getHumidity() {
        return $this->thHumidity;
    }

    public function getAttributes() {
        return array('Heating' => $this->thHeating,
                     'Mode' => $this->thMode,
                     'SetPoint' => $this->thSetPoint,
                     'Time' => $this->thTime,
                     'Temperature' => $this->thTemperature,
                     'Humidity' => $this->thHumidity
               );
    }
    public function __toString() {
        return json_encode($this->getAttributes());
    }
}

function printAllHeaders() {
    global $log;
    foreach ($_SERVER as $name => $value) {
        if (substr($name, 0, 5) == 'HTTP_') {
            $hName = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($name, 5)))));
            $log->debug("HTTP Header - name:".$hName." value:".$value);
        }
    }
}

function makeHttpCall($url, &$data, $method="GET", $contentType="text/plain", $timeout=5) {
    $params = "";
    if (in_array(gettype($data), array('array', 'object'))) {
        $params = http_build_query($data);
    }
    elseif (in_array(gettype($data), array('boolean', 'integer', 'double', 'string'))) {
        $params = $data;
    }

    $options = array(
        'http' => array(
            'header'  => "Content-type: $contentType\r\n",
            'method'  => $method,
            'content' => $params,
            'timeout' => $timeout
        )
    );

    global $log;
    $log->debug("HTTP Call URL.....: $url");
    $log->debug("HTTP Call Options.: ".json_encode($options));

    $context = stream_context_create($options);
    $result  = file_get_contents($url, false, $context);

    $log->debug("HTTP Call Response: $result");

    return ($result === FALSE) ? 500 : 0;
}

function updateItemState ($itemName, $itemState) {
    return makeHttpCall(REST_API."items/$itemName/state", $itemState, "PUT");
}

function updateThermostatStatus(&$thermostat) {
    $result = updateItemState("SMA_Thermo_Status_Heating", $thermostat->getHeating());
    if ($result == 0) {
        $result = updateItemState("SMA_Thermo_Status_SetMode", $thermostat->getMode());
    }
    if ($result == 0) {
        $result = updateItemState("SMA_Thermo_Status_SetPoint", $thermostat->getSetPoint());
    }
    if ($result == 0) {
        $result = updateItemState("SMA_Thermo_Status_SetTime", $thermostat->getTime());
    }
    if ($result == 0) {
        $result = updateItemState("SMA_Thermo_Measure_Temperature", $thermostat->getTemperature());
    }
    if ($result == 0) {
        $result = updateItemState("SMA_Thermo_Measure_Humidity", $thermostat->getHumidity());
    }
    return $result;
}

//printAllHeaders();

$body = file_get_contents('php://input');
$log->debug("Notification Body.: $body");

// receive the JSON Post data
$json = json_decode($body, true);

$respData = array();

if (isset($json[0]["eventType"]) && ($json[0]["eventType"] == "Microsoft.EventGrid.SubscriptionValidationEvent")) {
    // Azure subscription validation (https://docs.microsoft.com/en-us/azure/event-grid/security-authentication)
    $validationCode = $json[0]["data"]["validationCode"];
    $log->info(" Validation Code...: $validationCode");

    $respData = array('validationResponse' => $validationCode);
}
else {
    // Extract payload from notification
    $notification = $json[0]["data"]["chronothermostats"][0];

    // Parse notification into Thermostat object
    $thermostat = new ThermostatStatus($notification);
    $log->info(" Thermostat Status.: $thermostat");

    // Update remote thermostat status
    $result = updateThermostatStatus($thermostat);

    // Prepare notification response body
    $respData = array('result' => $result);
}

http_response_code(200);
header('Content-Type: application/json');

$resp = json_encode($respData);
$log->info(" Notification Reply: $resp");

echo $resp;
?>
