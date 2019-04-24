# openhab-smarther

[![Join the chat at https://gitter.im/openhab-smarther/community](https://badges.gitter.im/openhab-smarther/community.svg)](https://gitter.im/openhab-smarther/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Scripts created and operations performed to achieve integration between Bticino Smarther chronothermostat and OpenHAB v2 server, via Legrand's "Smarther - v2.0" API gateway. 

The following instructions are mapped to my environment, where I have:
- an OpenHAB v2.4 home server, running on Raspberry Pi 3 model B+
- an Nginx web server with PHP, running on Raspberry Pi 3 model B
- just one Smarther chronothermostat to be controlled 

Smarther chronothermostat (product code X8000) is produced by Bticino (https://www.smarther.bticino.it) and doesn't support the OpenWebNet protocol.

Legrand's "Smarther - v2.0" API need to be used instead: https://portal.developer.legrand.com/docs/services/smartherV2

## First steps

### Register a Developer account
Sign up for a new Developer account on Works with Legrand website (https://developer.legrand.com/login).

### Subscribe to Legrand APIs
Sign in, go to menu "API > Subscriptions" and make sure you have "Starter Kit for Legrand APIs" subscription activated; if not, activate it.

Go to menu "User > My Subscriptions" and show/write down your subscription's "Primary Key".

### Test the Smarther v2 API calls
Go to menu "API > APIs List", then choose the "Smarther - v2.0" thumb to access the APIs documentation and testbed.

Choose the "Plants" operation on the left menu, then the "Try It" button. Choose the "Authorization code" option in the Authorization section and click on "Send". Write down the value of plants.id attribute in the JSON response payload, as your thermostat "Plant ID".

Choose the "Topology" operation on the left menu, then the "Try It" button. Insert your Plant ID, choose the "Authorization code" option in the Authorization section and click on "Send". Write down the value of plant.modules[0].id attribute in the JSON response payload, as your thermostat "Module ID".

### Register a new application
Go to menu "User > My Applications" and click on "Create new" to register a new application:
- Insert a valid Url in "First Reply Url" as it will be called back by the OAuth authentication procedure (see below) 
- Make sure to tick the checkbox near scopes "comfort.read" and "comfort.write"

Submit your request and wait for a response via email from Legrand (it usually takes 1-2 days max).
If your app has been approved, you should find in the email your "Client ID" and "Client Secret" attributes.

**Note:** OAuth server will redirect the first step of authentication process to the First Reply Url you insert into new application registration form. Legrand will not allow you to change it at a later stage, thus make sure it points to the public Url of your smarther-auth.php script (see script installation section for more info).
In my case it is:

> First Reply Url = https://myWebServerIP:myWebServerPort/smarther/smarther-auth.php

## Script installation

### API script
Log into your OpenHab server, then create a directory "smarther" under your $OPENHAB_CONF/scripts/ directory and, inside it, the subdirectories "data" and "log":
```
mkdir $OPENHAB_CONF/scripts/smarther
mkdir $OPENHAB_CONF/scripts/smarther/data
mkdir $OPENHAB_CONF/scripts/smarther/log
```

Copy the smarther-api.sh script into smarther/ directory and give it execute grant, then change the owner of smarther/ branch:
```
chmod +x $OPENHAB_CONF/scripts/smarther/smarther-api.sh
sudo chown -R openhab:openhabian $OPENHAB_CONF/scripts/smarther/
```

### Web server script
Log into your Web server, then create a directory "smarther" under your webroot and a new logfile under /var/log/php.
In my case:
```
sudo mkdir /var/www/html/smarther/
sudo touch /var/log/php/smarther-c2c.log
```

Copy the smarther-auth.php and smarther-c2c.php script into smarther/ directory and assign the correct ownerships:
```
sudo chown -R www-data:adm /var/www/html/smarther/
sudo chown www-data:adm /var/log/php/smarther-c2c.log
```

## Configuration and authorization

### Script configuration
Open the smarther-api.sh script and update the "Configuration Section" with your actual values:
```
subscription_key="yourSubscriptionKey"
client_id="yourClientId"
client_secret="yourClientSecret"
redirect_uri="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-auth.php"
plant_id="thePlantIdOfYourHome"
module_id="theModuleIdOfYourThermostat"
notify_url="https://yourWebServerPublicIP:yourWebServerPort/smarther/smarther-c2c.php"
```
Then, open the smarther-c2c.php script and update the "Configuration Section" with your actual values:
```
define("REST_API", "http://yourOpenhabServerIP:yourOpenhabServerPort/rest/");
```

### One-time authorization process
1. Execute the smarther-api.sh script with no parameters, the first time you'll receive the following error message:
> OAuth2 code is missing or invalid. To restore the authentication flow call the following Url from a browser: < url >
2. Open the < url > in a browser and complete the OAuth2 authorization process, inserting your developer account credentials when needed.
3. If everything worked fine, you'll be redirected to your smarther-auth.php script, which should automatically download a file named "authorization.json".
4. Copy that file inside $OPENHAB_CONF/scripts/smarther/data/ directory.
5. Execute the smarther-api.sh script again with "get_status" parameter:
```
. ./smarther-api.sh get_status
```
6. If everything worked fine, you should get back the status of your chronothermostat; something like:
```
{"rsptype":"get_status","rspcode":200,"function":"HEATING","mode":"AUTOMATIC","setpoint":7,"program":1,"time":"forever","tempformat":"C","status":"INACTIVE","temperature":19.3,"humidity":43.5}
```

## Openhab files installation
Open PaperUI, go to Add-ons menu and add the following:
- Bindings > "Exec Binding"
- Transformations > "RegEx Transformation"
- Transformations > "JSONPath Transformation"

Now, go to Inbox > Exec Binding > Choose Thing > Command and create a new command with the following setup:
- Name = Smarther Thermostat
- Thing ID = smarther_api
- Location = (choose your preferred one)
- Command = /etc/openhab2/scripts/smarther/smarther-api.sh %2$s
- Interval = 0
- Timeout = 10
- Autorun = true

Then:
1. Copy the smarther.map in your $OPENHAB_CONF/transform/ directory
2. Copy the smarther.items file in your $OPENHAB_CONF/items/ directory
3. Merge the smarther.sitemap content with your "master" default.sitemap file
4. Copy the smarther.rules file in your $OPENHAB_CONF/rules/

You should now see the Smarther Chronothermostat in your Basic UI interface and start interacting with it.

One last step is needed to register your endpoint on the Legrand's remote gateway, to start receiving notifications and automatically change the value of your Smarther items according to the thermostat status provided by the remote gateway.

### Cloud 2 Cloud notifications
To register your smarther-c2c.php endpoint on MS Azure Cloud2Cloud notification server and start receiving notifications on changes to your chronothermostat status, do as follows:
1. Execute the smarther-api.sh script with "set_subscription" parameter
```
. ./smarther-api.sh set_subscription
```
2. If everything worked fine, you should get back the status of your subscription; something like:
```
{"rsptype":"set_subscription","rspcode":201,"subscriptions":{"subscriptionId":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}}
```

## Acknowledgments
- [Francesco Ranieri](https://community.openhab.org/u/francesco_ranieri/), for having pointed me in the right direction and a first [code sample](https://community.openhab.org/t/bticino-smarther-thermostat/39621/13) to start playing with.
