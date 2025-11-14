## Workstation installation

Quick How-To install a Galaxis/SYSTM workstation!

**What do you need?**
- a workstation with minimum Windows 10 installed.
- access to the local .\Administrator-user of the workstation, even if you plan to disable it later on.

---

**Steps**

1. If not yet done, activate the local Administrator-user and set a password.
2. Make sure that your workstation has the correct hostname, if it does not yet have - rename it.
3. Logon as the local Administrator. 
4. Make sure that UAC is disabled.
5. If you are not in a domain, open "C:\Windows\System32\drivers\etc\hosts" and enter the correct IPs and the corresponding hostnames of your installation:

Example:
```powershell
10.50.200.51    ModulusDB-BC    #DB 
10.50.200.50    ModulusAPP-BC   #APP
10.50.200.52    ModulusFS-BC    #FS/OL
```

6. Open "This PC" and add a permanent network-share "M:" using the Galaxis-share of your application server. Make sure that you log in with the Administrator-user of the application server.

Example:

\\\ModulusAPP-BC\Galaxis

7. Run "M:\Install\WrkStationSetup_W8.Ink" to start the workstation installation process

8. Verify if the Oracle installation was correctly executed by doing a "tnsping GLX" or "tnsping JKP". If you have another database name, adjust accordingly.

9. Verify the environment variables to make sure they were correctly set.

10. Test the applications by opening Data Setup, Back Office Slot Operation, etc.

11. If you need QB, install it using the file from M:\Install\ and deploy the prepared qb.cfg file to the installation path of your QueryBuilder.

12. Test QB.

13. If you need Jackpot Applications, install it them the files from M:\Install\Jackpot and deploy the prepared ini-files to the installation path of your JP Applications.

14. Test Jackpot Applications.

15. Make sure that the FrontCage.ini in the correct M:\Workstation\-folder is scorrectly setup.
