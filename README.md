# openhab-smarther
Scripts created and operations performed to achieve integration between Bticino Smarther chronothermostat and OpenHAB v2 server.

The following instructions are mapped to my environment, where I have:
- an OpenHAB v2.4 home server, running on Raspberry Pi 3 model B+
- a Nginx web server with PHP, running on Raspberry Pi 3 model B
- just one Smarther chronothermostat to be controlled 

Smarther chronothermostat (product code X8000) is produced by Bticino (https://www.smarther.bticino.it) and doesn't support the OpenWebNet protocol.

Legrand's "Smarther - v2.0" API need to be used instead: https://portal.developer.legrand.com/docs/services/smartherV2

## Create a Legrand application

### Register developer account

### Subscribe to API

### Submit application request (roles)

## Gather starting info

### Get topology details (plant, module)

### Get Authoeization
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
