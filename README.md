# openhab-smarther
Scripts created and operations performed to achieve integration between Bticino Smarther chronothermostat and OpenHAB v2 server.

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

> mkdir $OPENHAB_CONF/scripts/smarther
> mkdir $OPENHAB_CONF/scripts/smarther/data
> mkdir $OPENHAB_CONF/scripts/smarther/log

Copy the smarther-api.sh script into smarther/ directory and give it execute grant, then change the owner of smarther/ branch:

> chmod +x $OPENHAB_CONF/scripts/smarther/smarther-api.sh
> sudo chown -R openhab:openhabian $OPENHAB_CONF/scripts/smarther/

### Web server script
Log into your Web server, then create a directory "smarther" under your webroot and a new logfile under /var/log/php.
In my case:

> sudo mkdir /var/www/html/smarther/
> sudo touch /var/log/php/smarther-c2c.log

Copy the smarther-auth.php and smarther-c2c.php script into smarther/ directory and assign the correct ownerships:

> sudo chown -R www-data:adm /var/www/html/smarther/
> sudo chown www-data:adm /var/log/php/smarther-c2c.log

## Configuration and authorization

### Script configuration
TBD Oauth2 interation

### One-time authorization process

### Cloud 2 Cloud notifications
Register endpoint

## Openhab files installation
Files
Openhab exec thing setup
