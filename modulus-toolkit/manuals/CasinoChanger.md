## CasinoChanger v1.0

This tool is designed to help you to reconfigure the scope of an existing DB.
The goal is to change any casino-specific values like **COD_SOCIET**, **COD_ETABLI** and **CASINO_ID**.

In the most important tables the script also changes the casinos long and short names.
The script should be able to manage newer and older versions of GLX-DB. JKP-DB is not part of the scope.

---

**How does the script work:**

1. It will find all columns within the DB that it needs to change!
2. It will loop through all the related constraints for those coluns and disable them!
3. It will loop through all the columns and update them accordingly!
4. It will then update all the views, triggers and default values within the DB with the new CASINO_IDs!
5. It will then reactivate all the previously disabled constraints!

---

**How to use the script:**

1. **IMPORTANT** - Before working with the script: **CREATE A SNAPSHOT!**
2. Edit **C:\Program Files\PowerShell\Modules\modulus-toolkit\config\mod-VM-config.json** and fill in the wanted configuration for COD_SOCIET, COD_ETABLI, CASINO_ID and the long and short names!
3. Check the current database and look for the CASINO_ID you want to reconfigure.
4. In Powershell: Run **Execute-CasinoChanger** and follow the instructions within powershell.
5. Verify if the changes were made as expected!
6. Doublecheck!!!


**Potential improvements:**

1. Take care of IPs & hostnames!
2. Improve or limit the output, for example amount of constraints disabled vs amount of contraints enabled. Maybe spool it to a file?

**Feedback or questions?**

Don't hesitate to reach out to me.

**GLXHOST-Task:**

[GLXHOST-3002](https://modulusgroup.atlassian.net/browse/GLXHOST-3002)

---