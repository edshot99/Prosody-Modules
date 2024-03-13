---
labels:
- 'Stage-Beta'
...

Introduction
============

This module aims to help user password restoration.
To start the restoration, the user must go to an URL provided by this
module, fill the JID and email and submit the request.

The module will generate a token valid for 1h and send an email with a
specially crafted URL to the email address set in account details (not vCard).
If the user goes to this URL, the user will be able to change his password.

Usage
=====

Add "email\_pass" to your modules\_enabled list and copy the mod\_email\_pass
folder to the Prosody modules folder.

This module also requires the "email" module which you can find here:
https://modules.prosody.im/mod\_email.html

This module only sends emails to the user email address set in Prosody account
details.
The user must set this email address in order to be capable of do the
restoration by going to: /email\_pass/changemail.html

Configuration
=============

  ---------------  ------------------------------------------------------------ ---------------------
  token\_expire    Time in seconds before token expires                         3600
  attempt\_limit   Maximum attempts for 'update email'/'reset with token' page  10
  attempt\_wait    Time in seconds to block IP from going beyond limit          1800
  email\_pass\_url URL prefix used for sending the token                        https://hostname:5281
  ---------------  ------------------------------------------------------------ ---------------------

Compatibility
=============

  ----- -------
  0.12   Works
  0.9    Works
  ----- -------
