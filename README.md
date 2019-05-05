# openhab-smarther
Scripts created and operations performed to achieve integration between BTicino Smarther chronothermostat and OpenHAB v2 server, via Legrand's "Smarther - v2.0" API gateway. 

[![stable](http://badges.github.io/stability-badges/dist/stable.svg)](http://github.com/badges/stability-badges)

The following instructions are mapped to my environment, where I have:
- an OpenHAB v2.4 home server, installed on a Raspberry Pi 3 model B+ using openHABian v1.4.1
- an Nginx web server with PHP, installed on a Raspberry Pi 3 model B
- just one Smarther chronothermostat to be controlled 

Smarther chronothermostat (product code X8000) is produced by Bticino (https://www.smarther.bticino.it) and doesn't support the OpenWebNet protocol.

Legrand's "Smarther - v2.0" API need to be used instead: https://portal.developer.legrand.com/docs/services/smartherV2

## 1. First steps

### 1.1. Register a Developer account
Sign up for a new Developer account on Works with Legrand website (https://developer.legrand.com/login).

### 1.2. Subscribe to Legrand APIs
Sign in, go to menu "API > Subscriptions" and make sure you have "Starter Kit for Legrand APIs" subscription activated; if not, activate it.

Go to menu "User > My Subscriptions" and show/write down your subscription's "Primary Key".

### 1.3. Test the Smarther v2 API calls
Go to menu "API > APIs List", then choose the "Smarther - v2.0" thumb to access the APIs documentation and testbed.

Choose the "Plants" operation on the left menu, then the "Try It" button. Choose the "Authorization code" option in the Authorization section and click on "Send". Write down the value of `plants.id` attribute in the JSON response payload, as your thermostat "Plant ID".

Choose the "Topology" operation on the left menu, then the "Try It" button. Insert your Plant ID, choose the "Authorization code" option in the Authorization section and click on "Send". Write down the value of `plant.modules[0].id` attribute in the JSON response payload, as your thermostat "Module ID".

### 1.4. Register a new application
Go to menu "User > My Applications" and click on "Create new" to register a new application:
- Insert a valid **public** URL in "First Reply Url", as it will be called back later by the OAuth remote server (see [3.1](#31-bash-script-configuration))
- Make sure to tick the checkbox near scopes `comfort.read` and `comfort.write`

Submit your request and wait for a response via email from Legrand (it usually takes 1-2 days max).
If your app has been approved, you should find in the email your "Client ID" and "Client Secret" attributes.

**Note:** OAuth server will redirect the first step of authentication process to the First Reply Url you insert into new application registration form. Legrand will not allow you to change it at a later stage, thus make sure it points to the **public** URL of your smarther-auth.php script (see section [3.1](#31-bash-script-configuration) for more info).
In my case it is:
```
First Reply Url = https://myWebServerIP:myWebServerPort/smarther/smarther-auth.php
```

## 2. Script installation

### 2.1. API script
Log into your OpenHab server, then create a directory `smarther` under your `$OPENHAB_CONF/scripts/` directory and, inside it, the subdirectories `data` and `log`:
```
mkdir $OPENHAB_CONF/scripts/smarther
mkdir $OPENHAB_CONF/scripts/smarther/data
mkdir $OPENHAB_CONF/scripts/smarther/log
```

Copy the `smarther-api.sh` script into `smarther/` directory and give it execute grant, then change the owner of `smarther/` branch:
```
chmod +x $OPENHAB_CONF/scripts/smarther/smarther-api.sh
sudo chown -R openhab:openhabian $OPENHAB_CONF/scripts/smarther/
```

**Note:** the `chown` step is needed in my case as openHABian creates the "default" user `openhabian` while OH2 runs under `openhab` user; different installations could require to change the script ownership to `openhab:openhab`. In any case the ownership should be the same as the other files in your OH2 instance, otherwise the script called from within OH2 could fail updating its service json file.

### 2.2. Web server script
Log into your Web server, then create a directory `smarther` under your webroot and a new logfile under `/var/log/php`.
In my case:
```
sudo mkdir /var/www/html/smarther/
sudo touch /var/log/php/smarther-c2c.log
```

Copy the `smarther-auth.php` and `smarther-c2c.php` script into `smarther/` directory and assign the correct ownerships:
```
sudo chown -R www-data:adm /var/www/html/smarther/
sudo chown www-data:adm /var/log/php/smarther-c2c.log
```

## 3. Configuration and authorization

### 3.1. Bash script configuration
Open the `smarther-api.sh` script and update the "Configuration Section" with your actual values:
```
subscription_key="yourSubscriptionKey"
client_id="yourClientId"
client_secret="yourClientSecret"
redirect_uri="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-auth.php"
plant_id="thePlantIdOfYourHome"
module_id="theModuleIdOfYourThermostat"
notify_url="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-c2c.php"
```

**Note #1:** it could happen that your `client_secret` generated by Legrand server contains double quotes; in this case escaping them with a backslash would fix the setup. For example, if your secret is `xxxxx"yyyyy` you can configure it as follows:
```
client_secret="xxxxx\"yyyyy"
```
**Note #2:** both the `redirect_uri` and `notify_url` must point to a **public** URL. The 1st one is used in the OAuth authentication process and must contain the same value as the First Reply Url registered with the application (see sections [1.4](#14-register-a-new-application) and [3.3](#33-one-time-authorization-process)); The 2nd one will be later used by MS Azure cloud to push thermostat status notifications to your server (see section [4.1](#41-cloud-2-cloud-notifications)).

### 3.2. PHP script configuration
Open the `smarther-c2c.php` script and update the "Configuration Section" with your actual values:
```
define("REST_API", "http://yourOpenhabServerIP:yourOpenhabServerPort/rest/");
```

### 3.3. One-time authorization process
1. Execute the `smarther-api.sh` script with no parameters, the first time you'll receive the following error message:
> OAuth2 code is missing or invalid. To restore the authentication flow call the following Url from a browser: LongURL
2. Copy the `LongURL` URL, open it in a browser and complete the OAuth2 authorization process, inserting your developer account credentials when needed.
3. If everything worked fine, you'll be redirected to your `smarther-auth.php` script, which should automatically download a file named `authorization.json`.
4. Copy that JSON file inside `$OPENHAB_CONF/scripts/smarther/data/` directory.
5. Execute the `smarther-api.sh` script again with `get_status` parameter:
```
. ./smarther-api.sh get_status
```
6. If everything worked fine, you should get back the status of your chronothermostat; something like:
```
{"rsptype":"get_status","rspcode":200,"function":"HEATING","mode":"AUTOMATIC","setpoint":7,"program":1,"time":"forever","tempformat":"C","status":"INACTIVE","temperature":19.3,"humidity":43.5}
```

## 4. Openhab files installation
Open PaperUI, go to Add-ons menu and add the following:
- Bindings > "Exec Binding"
- Transformations > "RegEx Transformation"
- Transformations > "JSONPath Transformation"

Now, go to Inbox > Exec Binding > Choose Thing > Command and create a new command with the following setup:
- Name = `Smarther Thermostat`
- Thing ID = `smarther_api`
- Location = (choose your preferred one)
- Command = `/etc/openhab2/scripts/smarther/smarther-api.sh %2$s`
- Interval = `0`
- Timeout = `10`
- Autorun = `true`

Then:
1. Copy the `smarther.map` in your `$OPENHAB_CONF/transform/` directory
2. Copy the `smarther.items` file in your `$OPENHAB_CONF/items/` directory
3. Merge the `smarther.sitemap` content with your "master" `default.sitemap` file
4. Copy the `smarther.rules` file in your `$OPENHAB_CONF/rules/` directory

You should now see the Smarther Chronothermostat in your Basic UI interface and start interacting with it.

One last step is needed to register your endpoint on the Legrand's remote gateway, to start receiving notifications and automatically change the value of your Smarther items according to the thermostat status provided by the remote gateway.

### 4.1. Cloud 2 Cloud notifications
To register your `smarther-c2c.php` endpoint on MS Azure Cloud2Cloud notification server and start receiving notifications on changes to your chronothermostat status, do as follows:
1. Execute the `smarther-api.sh` script with `set_subscription` parameter
```
. ./smarther-api.sh set_subscription
```
2. If everything worked fine, you should get back the status of your subscription; something like:
```
{"rsptype":"set_subscription","rspcode":201,"subscriptions":{"subscriptionId":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}}
```

## 5. Acknowledgments
- [Francesco Ranieri](https://community.openhab.org/u/francesco_ranieri/), for having pointed me in the right direction and a first [code sample](https://community.openhab.org/t/bticino-smarther-thermostat/39621/13) to start playing with.
