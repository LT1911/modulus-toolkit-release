# QPoncash update checklist v0.1

Just to have a small growing list of things we need to check once we migrated and updated a casino.
This time for the QPoncash scope.

## Things to check:

## Services:
- Did all services start alright?
    - FS   
    - DB
    - APP
- Check in QB to see if all expected services are running and connected to their respective targets!

## EGMS:
- Are all EGMs connected to the FLOOR?
- Are the FW versions up2date or do we need to update? 
	- In case of major CMOD version update -> destroy config
- Test the following on the EGMS:
    - Can we insert money?
    - Can we print a ticket? Money correct on ticket?
    - Can we redeem a ticket? Money correct on credit meter according to ticket inserted?

## EGMS Player tracking:
- Player tracking/marketing tests on the EGMS:
	- Insert player card. Card accepted?
	- Player loyalty points are shown?
	- Possible to change settings like language, showing of points? Changed settings are stored for the player profile?
	- Play a defined number of credits/cash and check poinst rewarded
	- Card out and card in, check if points are stored in player profile

- Player tracking/marketing tests on workstations/in applications:
	- Search for player by name, first name, ID, etc
	- Swipe existing card to serach for player
	- Create new player with card printer or
	- Create new player via external API call from 3rd party system
	- Test new created player card on EGM if card is recognized

# EGMS Jackpots:
- Jackpot tests on the EGMS:
	- Play a defined even amount of cash on the EGM
	- Calculated required JP value increment and compare in QB and JP display/StarDISP

## New workstations:
- What is the hostname?
- Is it a preexistant worksation that was just replaced, is it a completely new one?
- Make sure you set it up using the workstation installation helper.
- Install all needed applications on it.
- Have the customer check it.

## QPoncash Manager:
- Open QPoncash Manager and log in
- Make sure the correct amount of EGMs and Kiosks are licensed

## Cage:
- Open FrontCage and log in
- Is the cage communicating with QPoncash service/Cash Wallet service?
- Is all the connected hardware installed and configured correctly?
- Do we have a printer, a barcodescanner, do we have a magnetic card reader? Which COM-ports and drivers are involved?
- Can we print a ticket, can we scan and redeem a ticket?
- Can we print a promotional ticket?

## Reception:
- Open Marketing Reception and log in
- Which hardware is needed at the respective workstation?
- Search a player, create a player!
- Print a promotional ticket, was it printed?

## Kiosk: 
- Redeem tickets and test any APIs that are involved!
- Swipe player card and check if player is found

## BOSO:
- Open BOSO and log in
- Check if meters were collected, do a proper check of the daily and hourly collections
- Check if the meters were properly integrated

## Site Security:
- Open Site Security and log in
- Make sure that newly added user rights are added the the appropriate user groups, especially the administrative user groups should have all rights! 

## SYSTM:
- Open a browser and log into SYSTM
- Check if all machines are properly displayed and that you have all needed firmware packages uploaded and defined as initial downloads.
- Test a FW download and make sure it works!
- Check special customer DB views if still there and delivers data

## FM:
- Check in with customer on what they use from this funcionality and make sure it still works as expected!

## StarDisplay:
- Check in with the customer on what they use from this functionality and make sure it still works as expected!
- There should not be any empty displays on the floor!

## Prepare everything so that every printed slip can be tested as soon as possible
- 

## Restart the services after the initial checks and workstation installations - it's never a bad idea!