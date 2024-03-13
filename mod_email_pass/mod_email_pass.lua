local dm_load = require "util.datamanager".load;
local st = require "util.stanza";
local nodeprep = require "util.encodings".stringprep.nodeprep;
local usermanager = require "core.usermanager";
local http = require "net.http";
local datetime = require "util.datetime";
local timer = require "util.timer";
local jidutil = require "util.jid";
local moduleapi = require "core.moduleapi";

local os_time = os.time;
local token_expire = module:get_option_number("token_expire", 3600);


-- This table has the tokens submited by the server
tokens_mails = {};
tokens_expiration = {};

-- URL
local email_pass_url = module:get_option_string("email_pass_url", "https://" .. module.host .. ":5281");

local timer_repeat = 120;		-- repeat after 120 secs

local account_details = module:open_store("account_details");

local attempt_limit = module:get_option_number("attempt_limit", 10);
local attempt_wait = module:get_option_number("attempt_wait", 1800);
attempt_wait_list = {};
attempt_wait_list_time = {};

module:depends("email");

function template(data)
	-- Like util.template, but deals with plain text
	return { apply = function(values) return (data:gsub("{([^}]+)}", values)); end }
end

local function get_template(name, extension)
	local fh = assert(module:load_resource("templates/"..name..extension));
	local data = assert(fh:read("*a"));
	fh:close();
	return template(data);
end

local function render(template, data)
	return tostring(template.apply(data));
end

local changemail_tpl = get_template("changemail",".html");
local changepass_tpl = get_template("changepass",".html");
local sendmail_success_tpl = get_template("sendmailok",".html");
local reset_success_tpl = get_template("resetok",".html");
local update_success_tpl = get_template("updateok",".html");
local token_tpl = get_template("token",".html");

function generate_page(event, lang, display_options)
	local request = event.request;

	-- begin translation
	if lang == "Español" then
		s_title = "Reseteo de la contraseña de tu cuenta Jabber";
		s_username = "Nombre de Usuario";
		s_usernamemessage = "Introduce tu nombre de usuario";
		s_email = "Email";
		s_emailmessage = "Introduce tu email";
		s_send = "¡Enviar!";
		s_text = "Al pulsar sobre el botón, se enviará a la dirección de correo que figura en tu cuenta un enlace en el que deberás entrar.";
	else
		s_title = "Reset your Jabber account password";
		s_username = "Username";
		s_usernamemessage = "Enter your username";
		s_email = "Email";
		s_emailmessage = "Enter your email";
		s_send = "Send!";
		s_text = "When you click the button, a link will be sent to the email address in your account.";
	end
	-- end translation

	return render(changepass_tpl, {
		path = request.path;
		hostname = module.host;
		notice = display_options and display_options.register_error or "";
		s_title = s_title;
		s_username = s_username;
		s_usernamemessage = s_usernamemessage;
		s_email = s_email;
		s_emailmessage = s_emailmessage;
		s_send = s_send;
		s_text = s_text;
		s_lang = lang;
	});
end

function generate_token_page(event, lang, display_options)
	local request = event.request;

	-- begin translation
	if lang == "Español" then
		s_title = "Reseto de la contraseña de tu cuenta Jabber";
		s_token = "Token";
		s_password = "Contraseña";
		s_passwordconfirm = "Contraseña (Confirmació)";
		s_change = "¡Cambiar!";
	else
		s_title = "Reset the password for your Jabber account";
		s_token = "Token";
		s_password = "Password";
		s_passwordconfirm = "Password (Confirm)";
		s_change = "Change!";
	end
	-- end translation

	return render(token_tpl, {
		path = request.path;
		hostname = module.host;
		token = request.url.query;
		notice = display_options and display_options.register_error or "";
		s_title = s_title;
		s_token = s_token;
		s_password = s_password;
		s_passwordconfirm = s_passwordconfirm;
		s_change = s_change;
		s_lang = lang;
	});
end

function generate_mail_page(event, lang, display_options)
	local request = event.request;

	-- begin translation
	if lang == "Español" then
		s_title = "Cambiar la eMail de tu cuenta Jabber";
		s_username = "Nombre de Usuario";
		s_usernamemessage = "Introduce tu nombre de usuario";
		s_password = "Contraseña";
		s_passwordmessage = "Introduce tu contraseña";
		s_email = "Email";
		s_emailmessage = "Introduce tu email";
		s_change = "¡Cambiar!";
	else
		s_title = "Change the eMail of your Jabber account";
		s_username = "Username";
		s_usernamemessage = "Enter your username";
		s_password = "Password";
		s_passwordmessage = "Enter your password";
		s_email = "Email";
		s_emailmessage = "Enter your email";
		s_change = "Change!";
	end
	-- end translation

	return render(changemail_tpl, {
		path = request.path;
		hostname = module.host;
		notice = display_options and display_options.register_error or "";
		s_title = s_title;
		s_username = s_username;
		s_usernamemessage = s_usernamemessage;
		s_password = s_password;
		s_passwordmessage = s_passwordmessage;
		s_email = s_email;
		s_emailmessage = s_emailmessage;
		s_change = s_change;
		s_lang = lang;
	});
end

function generateToken(address)
	math.randomseed(os.time())
	length = 16

	if length < 1 then return nil end

	local array = {}
	for i = 1, length, 2 do
		array[i] = string.char(math.random(48,57))
			array[i+1] = string.char(math.random(97,122))
	end

	local token = table.concat(array);
	if not tokens_mails[token] then
		tokens_mails[token] = address;
		tokens_expiration[token] = os.time();
		return token
	else
		module:log("error", "Reset password token collision: '%s'", token);
		return generateToken(address)
	end
end

function isExpired(token)
	if not tokens_expiration[token] then
		return nil;
	end
	if os.difftime(os.time(), tokens_expiration[token]) < token_expire then
		-- token is valid yet
		return nil;
	else
		-- token invalid, we can create a fresh one.
		return true;
	end
end

-- Expire tokens
expireTokens = function()
	for token,value in pairs(tokens_mails) do
		if isExpired(token) then
			module:log("info", "Expiring password reset request from user '%s', not used.", tokens_mails[token]);
			tokens_mails[token] = nil;
			tokens_expiration[token] = nil;
		end
	end
	return timer_repeat;
end

-- Check if a user has a active token not used yet.
function hasTokenActive(address)
	for token,value in pairs(tokens_mails) do
		if address == value and not isExpired(token) then
			return token;
		end
	end
	return nil;
end

function generateUrl(token, path)
	local url;

	url = email_pass_url .. path .. "token.html?" .. token;

	return url;
end

function sendMessage(jid, subject, message)
	local msg = st.message({ from = module.host; to = jid; }):
		tag("subject"):text(subject):up():
		tag("body"):text(message);
	module:send(msg);
end

function send_token_mail(form, origin)
	if form.langchange == "true" then
		return nil;
	end

	local lang = form.lang;
	local prepped_username = nodeprep(form.username, true);
	local prepped_mail = form.email;
	local jid = prepped_username .. "@" .. module.host;

	if not prepped_username then
		-- begin translation
		if lang == "Español" then
			return nil, "El nombre de usuario contiene caracteres incorrectos";
		else
			return nil, "The username contains invalid characters";
		end
		-- end translation
	end
	if #prepped_username == 0 then
		-- begin translation
		if lang == "Español" then
			return nil, "El campo texto de nombre de usuario está vacío";
		else
			return nil, "The username text field is empty";
		end
		-- end translation
	end
	if not usermanager.user_exists(prepped_username, module.host) then
		-- begin translation
		if lang == "Español" then
			return nil, "El usuario no existe";
		else
			return nil, "The user does not exist";
		end
		-- end translation
	end

	if #prepped_mail == 0 then
		-- begin translation
		if lang == "Español" then
			return nil, "El campo texto de email está vacío";
		else
			return nil, "The email text field is empty";
		end
		-- end translation
	end

	local account_detail_table = account_details:get(prepped_username);
	if account_detail_table == nil then
		account_detail_table = {["email"] = ""};
	end
	local account_detail_email = account_detail_table["email"];
	if not account_detail_email then
		-- begin translation
		if lang == "Español" then
			return nil, "El cuente no tiene ningún email configurado";
		else
			return nil, "The account has no email configured";
		end
		-- end translation
	end
	email = string.lower( account_detail_email );

	if #email == 0 then
		-- begin translation
		if lang == "Español" then
			return nil, "El cuente no tiene ningún email configurado";
		else
			return nil, "The account has no email configured";
		end
		-- end translation
	end

	if email ~= string.lower(prepped_mail) then
		-- begin translation
		if lang == "Español" then
			return nil, "eMail incorrecta";
		else
			return nil, "Incorrect eMail";
		end
		-- end translation
	end

	-- Check if has already a valid token, not used yet.
	if hasTokenActive(jid) then
		local valid_until = tokens_expiration[hasTokenActive(jid)] + token_expire;
		-- begin translation
		if lang == "Español" then
			return nil, "Ya tienes una petición de reseteada de contraseña, válida hasta: " .. datetime.date(valid_until) .. " " .. datetime.time(valid_until);
		else
			return nil, "You already have a password reset request, valid until: " .. datetime.date(valid_until) .. " " .. datetime.time(valid_until);
		end
		-- end translation
	end

	local url_path = origin.path;
	local url_token = generateToken(jid);
	local url = generateUrl(url_token, url_path);

	local mail_subject = nil;
	local mail_body = nil;
	-- begin translation
	if lang == "Español" then
		mail_subject = "Jabber/XMPP - Reseto de la Contraseña";
		mail_body = render( get_template("sendtoken", ".mail"), {jid = jid, url = url, time = ((token_expire / 60) / 60), host = module.host} );
	else
		mail_subject = "Jabber/XMPP - Password Reset";
		mail_body = render( get_template("sendtoken-en", ".mail"), {jid = jid, url = url, time = ((token_expire / 60) / 60), host = module.host} );
	end
	-- end translation

	module:log("info", "Sending password reset mail to user %s", jid);
	local ok, err = moduleapi:send_email({to = email, subject = mail_subject, body = mail_body});
	if not ok then
		module:log("error", "Failed to deliver to %s: %s", tostring(address), tostring(err));
	end

	-- begin translation
	if lang == "Español" then
		mail_subject = "Gestión de Cuentas";
		mail_body = "Token para reseto su contraseña ha sido enviado a su email por el sistema de reseto de contraseña.";
	else
		mail_subject = "Account Management";
		mail_body = "Token to reset your password has been sent to your email by password reset system.";
	end
	-- end translation

	sendMessage(jid, mail_subject, mail_body);

	return "ok";
end

function reset_password_with_token(form, origin)
	local lang = form.lang;

	if form.langchange == "true" then
		return nil;
	end
	if attempt_wait_list[origin.ip] == nil then attempt_wait_list[origin.ip] = 0; end
	if attempt_wait_list[origin.ip] >= attempt_limit then
		if os.difftime(os.time(), attempt_wait_list_time[origin.ip]) > attempt_wait then
			attempt_wait_list[origin.ip] = 0;
			attempt_wait_list_time[origin.ip] = 0;
		else
			module:log("info", "Too many attempts at guessing token from IP %s", origin.ip);
			-- begin translation
			if lang == "Español" then
				return nil, "Demasiados intentos. Inténtalo otra vez en "..(attempt_wait / 60).."m.";
			else
				return nil, "Too many attempts. Try again in "..(attempt_wait / 60).."m.";
			end
			-- end translation
		end
	end

	local token = form.token;
	local password = form.newpassword;
	local passwordconfirmation = form.newpasswordconfirmation;
	form.newpassword, form.newpasswordconfirmation = nil, nil;

	if not token then
		-- begin translation
		if lang == "Español" then
			return nil, "El Token es inválido";
		else
			return nil, "The token is invalid";
		end
		-- end translation
	end
	if not tokens_mails[token] then
		attempt_wait_list[origin.ip] = attempt_wait_list[origin.ip]+1;
		attempt_wait_list_time[origin.ip] = os.time();

		-- begin translation
		if lang == "Español" then
			return nil, "El Token no existe o ya fué usado";
		else
			return nil, "The token does not exist or has already been used";
		end
		-- end translation
	end
	if not password then
		-- begin translation
		if lang == "Español" then
			return nil, "El campo texto de contraseña está vacío";
		else
			return nil, "The password text field is empty";
		end
		-- end translation
	end
	if #password < 5 then
		-- begin translation
		if lang == "Español" then
			return nil, "El contraseña debe tener una longitud de al menos cinco caracteres";
		else
			return nil, "The password must be at least five characters long";
		end
		-- end translation
	end
	if password ~= passwordconfirmation then
		-- begin translation
		if lang == "Español" then
			return nil, "El confirmació de contraseña es inválido";
		else
			return nil, "The password confirmation is invalid";
		end
		-- end translation
	end
	local jid = tokens_mails[token];
	local user, host, resource = jidutil.split(jid);

	local mail_subject = nil;
	local mail_body = nil;

	-- begin translation
	if lang == "Español" then
		mail_subject = "Gestión de Cuentas";
		mail_body = "La contraseña se ha cambiado con el sistema de reseto de contraseña.";
	else
		mail_subject = "Account Management";
		mail_body = "Password has been changed with password reset system.";
	end
	-- end translation

	usermanager.set_password(user, password, host);
	module:log("info", "Password changed with token for user %s", jid);
	tokens_mails[token] = nil;
	tokens_expiration[token] = nil;
	sendMessage(jid, mail_subject, mail_body);

	-- begin translation
	if lang == "Español" then
		mail_subject = "Jabber/XMPP - Contraseña Cambiado";
		mail_body = render( get_template("updatepass", ".mail"), {jid = jid, host = module.host} );
	else
		mail_subject = "Jabber/XMPP - Password Changed";
		mail_body = render( get_template("updatepass-en", ".mail"), {jid = jid, host = module.host} );
	end
	-- end translation

	module:log("info", "Sending password update mail to user %s", jid);
	local ok, err = moduleapi:send_email({to = email, subject = mail_subject, body = mail_body});
	if not ok then
		module:log("error", "Failed to deliver to %s: %s", tostring(address), tostring(err));
	end

	return "ok";
end

function change_mail_with_password(form, origin)
	local lang = form.lang;

	if form.langchange == "true" then
		return nil;
	end
	if attempt_wait_list[origin.ip] == nil then attempt_wait_list[origin.ip] = 0; end
	if attempt_wait_list[origin.ip] >= attempt_limit then
		if os.difftime(os.time(), attempt_wait_list_time[origin.ip]) > attempt_wait then
			attempt_wait_list[origin.ip] = 0;
			attempt_wait_list_time[origin.ip] = 0;
		else
			module:log("info", "Too many attempts at guessing password from IP %s", origin.ip);
			-- begin translation
			if lang == "Español" then
				return nil, "Demasiados intentos. Inténtalo otra vez en "..(attempt_wait / 60).."m";
			else
				return nil, "Too many attempts. Try again in "..(attempt_wait / 60).."m";
			end
			-- end translation
		end
	end

	local prepped_username = nodeprep(form.username, true);
	local prepped_mail = form.email;
	local password = form.password;
	local jid = prepped_username .. "@" .. module.host;
	form.password = nil;

	if not prepped_username then
		-- begin translation
		if lang == "Español" then
			return nil, "El nombre de usuario contiene caracteres incorrectos";
		else
			return nil, "The username contains invalid characters";
		end
		-- end translation
	end
	if #prepped_username == 0 then
		-- begin translation
		if lang == "Español" then
			return nil, "El campo texto de nombre de usuario está vacio";
		else
			return nil, "The username text field is empty";
		end
		-- end translation
	end
	if not usermanager.user_exists(prepped_username, module.host) then
		-- begin translation
		if lang == "Español" then
			return nil, "El usuario no existe";
		else
			return nil, "The user does not exist";
		end
		-- end translation
	end

	if not password then
		-- begin translation
		if lang == "Español" then
			return nil, "El campo texto de contraseña está vacío";
		else
			return nil, "The password text field is empty";
		end
		-- end translation
	end


	if usermanager.test_password(prepped_username, module.host, password) then
		local account_detail_table = account_details:get(prepped_username);
		if account_detail_table == nil then
			account_detail_table = {["email"] = ""};
		end
		local remove_email;
		if prepped_mail == "" then
			remove_email = true;
		else
			remove_email = false;
		end
		email = string.lower(prepped_mail);
		account_detail_table["email"] = email;
		account_details:set(prepped_username, account_detail_table);
		module:log("info", "Email changed with password for user %s", jid);

		local mail_subject = nil;
		local mail_body = nil;

		-- begin translation
		if lang == "Español" then
			mail_subject = "Gestión de Cuentas";
			mail_body = "El email se ha actualizado a <"..email.."> con el sistema de reseto de contraseña.";
		else
			mail_subject = "Account Management";
			mail_body = "Email has been updated to <"..email.."> with password reset system.";
		end
		-- end translation

		sendMessage(jid, mail_subject, mail_body);

		if not remove_email then
			-- begin translation
			if lang == "Español" then
				mail_subject = "Jabber/XMPP - Email Cambiado";
				mail_body = render( get_template("updatemail", ".mail"), {jid = jid, email = email, host = module.host} );
			else
				mail_subject = "Jabber/XMPP - Email Changed";
				mail_body = render( get_template("updatemail-en", ".mail"), {jid = jid, email = email, host = module.host} );
			end
			-- end translation

			module:log("info", "Sending email update mail to user %s", jid);
			local ok, err = moduleapi:send_email({to = email, subject = mail_subject, body = mail_body});
			if not ok then
				module:log("error", "Failed to deliver to %s: %s", tostring(address), tostring(err));
			end
		end

		return "ok";
	else
		attempt_wait_list[origin.ip] = attempt_wait_list[origin.ip]+1;
		attempt_wait_list_time[origin.ip] = os.time();

		-- begin translation
		if lang == "Español" then
			return nil, "Contraseña incorrecta";
		else
			return nil, "Incorrect password";
		end
		-- end translation
	end
end

function generate_success(event, lang, username)
	-- begin translation
	if lang == "Español" then
		s_title = "¡Enlace enviado!";
		s_text = "Acabamos de enviarte un email con un enlace que tendrás que visitar.";
	else
		s_title = "Link sent!";
		s_text = "We just sent you an email with a link you’ll need to visit.";
	end
	-- end translation

	return render(sendmail_success_tpl, {
		jid = nodeprep(username, true).."@"..module.host;
		s_title = s_title;
		s_text = s_text;
	});
end

function generate_register_response(event, form, ok, err)
	local message;
	if ok then
		return generate_success(event, form.lang, form.username);
	else
		return generate_page(event, form.lang, { register_error = err });
	end
end

function handle_form_token(event)
	local request, response = event.request, event.response;
	local form = http.formdecode(request.body);

	local token_ok, token_err = send_token_mail(form, request);
	response:send(generate_register_response(event, form, token_ok, token_err));

	return true; -- Leave connection open until we respond above
end

function generate_reset_success(event, lang)
	-- begin translation
	if lang == "Español" then
		s_title = "¡Contraseña reseteada!";
		s_p1 = "Tu contraseña ha sido cambiada.";
		s_p2 = "Ya puedes iniciar sesión de Jabber.";
	else
		s_title = "Password reset!";
		s_p1 = "Your password has been changed.";
		s_p2 = "You can now log into Jabber.";
	end
	-- end translation

	return render(reset_success_tpl, {
		s_title = s_title;
		s_p1 = s_p1;
		s_p2 = s_p2;
	});
end

function generate_update_success(event, lang, email)
	-- begin translation
	if lang == "Español" then
		s_title = "¡Email cambiada!";
		s_p1 = "Tu email ha sido cambiada.";
		s_p2 = "Nuevo email";
	else
		s_title = "Email changed!";
		s_p1 = "Your email has been changed.";
		s_p2 = "New email";
	end
	-- end translation
	return render(update_success_tpl, {
		s_title = s_title;
		s_p1 = s_p1;
		s_p2 = s_p2;
		email = email;
	});
end

function generate_reset_response(event, form, ok, err)
	local message;
	if ok then
		return generate_reset_success(event, form.lang);
	else
		return generate_token_page(event, form.lang, { register_error = err });
	end
end

function generate_update_response(event, form, ok, err)
	local message;
	if ok then
		return generate_update_success(event, form.lang, form.email);
	else
		return generate_mail_page(event, form.lang, { register_error = err });
	end
end

function handle_form_reset(event)
	local request, response = event.request, event.response;
	local form = http.formdecode(request.body);

	local reset_ok, reset_err = reset_password_with_token(form, request);
	response:send(generate_reset_response(event, form, reset_ok, reset_err));

	return true; -- Leave connection open until we respond above
end

function handle_form_mailchange(event)
	local request, response = event.request, event.response;
	local form = http.formdecode(request.body);

	local change_ok, change_err = change_mail_with_password(form, request);
	response:send(generate_update_response(event, form, change_ok, change_err));

	return true; -- Leave connection open until we respond above
end

timer.add_task(timer_repeat, expireTokens);

module:provides("http", {
	route = {
		["GET /style.css"] = render(get_template("style",".css"), {});
		["GET /changepass.html"] = generate_page;
		["GET /changemail.html"] = generate_mail_page;
		["GET /token.html"] = generate_token_page;
		["GET /"] = generate_page;
		["POST /changepass.html"] = handle_form_token;
		["POST /changemail.html"] = handle_form_mailchange;
		["POST /token.html"] = handle_form_reset;
		["POST /"] = handle_form_token;
	};
});


