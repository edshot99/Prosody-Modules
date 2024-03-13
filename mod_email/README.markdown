---
labels:
- 'Stage-Stable'
...

Introduction
------------

Gives server owners and module developers the ability to send emails.

Usage
-----

For users and developers, add the following to your configuration file and
edit depending on your SMTP setup:

smtp = {
	origin = "username@hostname.domainname";

	-- Use sendmail and have sendmail handle SMTP
	exec = "/usr/sbin/sendmail";

	-- Use SMTP directly
	--user = "username";
	--password = "password";
	--server = "localhost";
	--port = 25;
	--domain = "hostname.domainname";
}

For developers you can do something like this to send emails from your module:

local moduleapi = require "core.moduleapi";
module:depends("email");
local ok, err = moduleapi:send_email({to = mail_address, subject = mail_subject, body = mail_body});
if not ok then
	module:log("error", "Failed to deliver to %s: %s", tostring(mail_address), tostring(err));
end

Todo
----

- Loading socket.smtp causes a stack trace on Prosody start up.
  Everything still works fine, but this should probably be fixed.

- No SSL/STARTTLS support. This will require implementing something like LuaSec.
  If needed, I would recommend to just set up OpenSMTPD and use sendmail.

Compatibility
-------------

  ----- --------------
  0.12  Works
  ----- --------------
