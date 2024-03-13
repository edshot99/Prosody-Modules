---
labels:
- 'Stage-Alpha'
summary: A web interface to register user accounts
rockspec:
  build:
    copy_directories:
    - templates
...

Introduction
------------

There are various reasons to prefer web registration instead of
"in-band" account registration over XMPP. For example the lack of
CAPTCHA support in clients and servers.

Details
-------

mod\_register\_web has Prosody serve a web page where users can sign up
for an account. It implements a CAPTCHA system to prevent automated
sign-ups (from bots, etc.).

Configuration
-------------

The module is served on Prosody's default HTTP ports at the path
`/register_web`. More details on configuring HTTP modules in Prosody can
be found in our [HTTP documentation](https://prosody.im/doc/http).

To configure the CAPTCHA you need to supply a 'captcha\_options' option:

        captcha_options = {
          -- provider = "recaptcha";
          -- recaptcha_private_key = "12345";
          -- recaptcha_public_key = "78901";

          -- provider = "hcaptcha";
          -- hcaptcha_private_key = "12345";
          -- hcaptcha_public_key = " 78901";

          ---- Default if no reCaptcha or hCaptcha options are set
          -- provider = "simplecaptcha";
        }

To only allow registration through this module, enter in the following
to your configuration:

registration_web_only = true

Customization
-------------

Copy the files in mod_register_web/templates/ to a new directory. Edit them,
and set `register_web_template = "/path/to/your/custom-templates"` in your
config file.

Compatibility
-------------

  ----- --------------
  0.12  Works
  0.10  Works
  0.9   Works
  0.8   Doesn't work
  ----- --------------

Todo
----

Different CAPTCHA implementation support

Collection of additional data, such as email address

The module kept simple!
