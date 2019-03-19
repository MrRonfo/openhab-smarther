# openhab-smarther
Scripts created and operations performed to achieve integration between Bticino Smarther chronothermostat and OpenHAB v2 server.

The following instructions are mapped to my environment, where I have:
- an OpenHAB v2.4 home server, running on Raspberry Pi 3 model B+
- a Nginx web server with PHP, running on Raspberry Pi 3 model B
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

## Gather starting info

### Get Authorization
TBD Oauth2 interation

### Get and save access token
Refresh.json

## Script installation

### Install shell script
Path

### Install php script
Path

### Cloud 2 Cloud notifications
Register endpoint

## Openhab files installation
Files
Openhab exec thing setup
