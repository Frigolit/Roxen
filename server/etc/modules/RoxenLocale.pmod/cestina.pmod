#charset iso-8859-2
/*
 * $Id: cestina.pmod,v 1.2 2000/03/10 22:30:21 hop Exp $
 *
 * Roxen locale support -- Cestina (Czech)
 *
 * Honza Petrous 1999-12-15
 *
 * Poznamka: Preklad neni nic moc, chtelo by to nejaky
 *           slovnik odbornych vyrazu :-(
 */
inherit RoxenLocale.standard;
constant name="cestina";
constant language = "Jazyk";
constant latin1_name = "cestina"; //"�e�tina";
constant encoding = "iso-8859-2";

class _base_server {
  inherit standard::_base_server;       // Fallback.

  // base_server/roxen.pike
  string uncaught_error(string bt) {
    return("Nezachytiteln� chyba v ovlada�i vl�kna: " + bt +
	   "Klient nedostane ��dnou odpov��.\n");
  }
  string supports_bad_include(string file) {
    return("Supports: Nelze na��st/vlo�it soubor "+file+"\n");
  }
  string supports_bad_regexp(string bt) {
    return(sprintf("Chyba p�i interpretaci datab�ze supports regexp:\n%s\n", bt));
  }
  string replacing_supports() { return("Nahra�en soubor etc/supports"); }
  string unique_uid_logfile() { return("Unik�tn� user ID logfile.\n"); }
  string no_servers_enabled() { return("<B>��dn� virtu�ln� server nen� aktivov�n.</B>\n"); }
  string full_status(string real_version, int boot_time,
		     int days, int hrs, int min, int sec, string sent_data,
		     float kbps, string sent_headers, int num_requests,
		     float rpm, string received_data) {
    return(sprintf("<table>"
		   "<tr><td><b>Verze:</b></td><td colspan=2>%s</td></tr>\n"
		   "<tr><td><b>Start:</b></td><td colspan=2>%s</td></tr>\n"
		   "<tr><td><b>On-line:</b></td>"
		   "<td colspan=2>%d dn�%s, %02d:%02d:%02d</td></tr>\n"
		   "<tr><td colspan=3>&nbsp;</td></tr>\n"
		   "<tr><td><b>Data out:</b></td><td>%s"
		   "</td><td>%.2f Kbit/sec</td></tr><tr>\n"
		   "<td><b>Hlavi�ky out:</b></td><td>%s</td></tr>\n"

		   "<tr><td><b>Po�et p��stup�:</b></td>"
		   "<td>%8d</td><td>%.2f/min</td></tr>\n"
		   "<tr><td><b>Data in:</b></td>"
		   "<td>%s</td></tr>\n"
		   "</table>",
		   real_version, ctime(boot_time),
		   days, "", hrs, min, sec,
		   sent_data, kbps, sent_headers,
		   num_requests, rpm, received_data));
  }

  string setting_uid_gid_permanently(int uid, int gid, string uname, string gname) {
    return("Permanentn� nastaveno uid na "+uid+" ("+uname+")"+
	   (gname ? " a gid na "+gid+" ("+gname+")" : "")+" .\n");
  }

  string setting_uid_gid(int uid, int gid, string uname, string gname) {
    return("Nastaveno uid na "+uid+" ("+uname+")"+
	   (gname ? " a gid na "+gid+" ("+gname+")" : "")+".\n");
  }

  string error_enabling_configuration(string config, string bt) {
    return("Chyba p�i startu konfigurace "+config+
	   (bt ? ":\n" + bt : "\n"));
  }

  string disabling_configuration(string config) {
    return("Zastaven� star� konfigurace " + config + "\n");
  }

  string enabled_server(string server) {
    return("Enabled the virtual server \"" +server + "\".\n");
  }

  string opening_low_port() {
    return("Otev�en� portu pod 1024");
  }

  string url_format() {
    return("URL mus� b�t v n�sleduj�c�m form�tu: protocol://computer[:port]/");
  }

  // base_server/configuration.pike
  string failed_to_open_logfile(string logfile) {
    return("Nelze otev��t �urn�l. ("+logfile+")\n" +
	   "�urn�lov�n� nebude aktivn�!\n");
  }
  string config_status(float sent_data, float kbps, float sent_headers,
		       int num_requests, float rpm, float received_data) {
    return(sprintf("<tr align=right><td><b>Data out:</b></td><td>%.2fMB"
                   "</td><td>%.2f Kbit/sec</td>"
		   "<td><b>Hlavi�ky out:</b></td><td>%.2fMB</td></tr>\n"
		   "<tr align=right><td><b>Po�et p��stup�:</b></td>"
		   "<td>%8d</td><td>%.2f/min</td>"
		   "<td><b>Data in:</b></td><td>%.2fMB</td></tr>\n",
		   sent_data, kbps, sent_headers,
  		   num_requests, rpm, received_data));
  }
  string ftp_status(int total_users, float upm, int num_users) {
    return(sprintf("<tr align=right><td><b>FTP u�ivatel� (celkem):</b></td>"
		   "<td>%8d</td><td>%.2f/min</td>"
		   "<td><b>FTP u�ivatel� (nyn�):</b></td><td>%d</td></tr>\n",
		   total_users, upm, num_users));
  }
  string ftp_statistics() {
    return("<b>FTP statistika:</b>");
  }
  string ftp_stat_line(string cmd, int times) {
    return(sprintf("<tr align=right><td><b>%s</b></td>"
		   "<td align=right>%d</td><td> time%s</td></tr>\n",
		   cmd, times, ""));
  }
  string no_auth_module() {
    return("Nen� autoriza�n� modul");
  }
  string module_security_error(string bt) {
    return(sprintf("Chyba p�i kontrole bezpe�nosti modulu:\n"
		   "%s\n", bt));
  }
  string clear_memory_cache_error(string modname, string bt) {
    return(sprintf("clear_memory_caches() pro modul %O:\n"
		   "%s neprob�hlo\n", modname, bt));
  }
  string returned_redirect_to(string location) {
    return("Vr�ceno p�esm�rov�n� (redirect) na " + location+"\n" );
  }
  string returned_redirect_no_location() {
    return("Vr�ceno p�esm�rov�n� (redirect), ale chyb� hlavi�ka Location\n");
  }
  string returned_authenticate(string auth) {
    return("Vr�cena chybn� autentizace: " + auth + "\n");
  }
  string returned_auth_failed() {
    return("Vr�cena chybn� authentizace.\n");
  }
  string returned_ok() {
    return("Vr�ceno ok\n");
  }
  string returned_error(int errcode) {
    return("Vr�ceno " + errcode + ".\n");
  }
  string returned_no_data() {
    return("Chyb� data ");
  }
  string returned_bytes(int len) {
    return(len + " bytes ");
  }
  string returned_unknown_bytes() {
    return("? bytes");
  }
  string returned_static_data() {
    return(" (static)");
  }
  string returned_open_file() {
    return "(open file)";
  }
  string returned_type(string type) {
    return(" of " + type + "\n");
  }
  string request_for(string path) {
    return("Request for " + path);
  }
  string magic_internal_gopher() {
    return("Magic internal gopher image");
  }
  string magic_internal_roxen() {
    return("Magic internal roxen image");
  }
  string magic_internal_module_location() {
    return("Magic internal module location");
  }
  string directory_module() {
    return("Directory module");
  }
  string returning_data() {
    return("Returning data");
  }
  string url_module() {
    return("URL module");
  }
  string too_deep_recursion() {
    return("Moc hlubok� rekurze");
  }
  string extension_module(string ext) {
    return("Extension module [" + ext + "] ");
  }
  string returned_fd() {
    return("Returned open filedescriptor.");
  }
  string seclevel_is_now(int slevel) {
    return(" Bezpe�nostn� �rove� je nyn� " + slevel + ".");
  }
  string location_module(string loc) {
    return("Location module [" + loc + "] ");
  }
  string module_access_denied() {
    return("P��stup k modulu odep�en.");
  }
  string request_denied() {
    return("Request denied.");
  }
  string calling_find_file() {
    return("Calling find_file()...");
  }
  string find_file_returned(mixed fid) {
    return(sprintf("find_file has returned %O", fid));
  }
  string calling_find_internal() {
    return("Calling find_internal()...");
  }
  string find_internal_returned(mixed fid) {
    return(sprintf("find_internal has returned %O", fid));
  }
  string returned_directory_indicator() {
    return("Returned directory indicator.");
  }
  string automatic_redirect_to_location() {
    return("Automatic redirect to location_module.");
  }
  string no_magic() {
    return("No magic requested. Returning -1.");
  }
  string no_directory_module() {
    return("Chyb� directory modul. Vr�ceno 'no such file'");
  }
  string permission_denied() {
    return("P��stup odep�en");
  }
  string returned_new_fd() {
    return("Vr�cen nov� otev�en� soubor.");
  }
  string content_type_module() {
    return("Content-type mapping module");
  }
  string returned_mime_type(string t1, string t2) {
    return("Vr�cen typ " + t1 + " " + t2 + ".");
  }
  string missing_type() {
    return("Typ chyb�.");
  }
  string returned_not_found() {
    return("Vr�ceno 'no such file'.");
  }
  string filter_module() {
    return("Filter module");
  }
  string rewrote_result() {
    return("V�sledek p�eps�n.");
  }
  string list_directory(string dir) {
    return(sprintf("V�pis adres��e %O.", dir));
  }
  string returned_no_thanks() {
    return("Vr�ceno 'No thanks'.");
  }
  string recursing() {
    return("Recurze");
  }
  string got_exclusive_dir() {
    return("Got exclusive directory.");
  }
  string returning_file_list(int num_files) {
    return("Vr�cen v�pis " + num_files + " soubor�.");
  }
  string got_files() {
    return("Got files.");
  }
  string added_module_mountpoint() {
    return("Added module mountpoint.");
  }
  string returning_no_dir() {
    return("Vr�ceno 'No such directory'.");
  }
  string stat_file(string file) {
    return(sprintf("Stat file %O.", file));
  }
  string exact_match() {
    return("Exact match.");
  }
  string stat_ok() {
    return("Stat ok.");
  }
  string find_dir_stat(string file) {
    return("Request for directory and stat's \""+file+"\".");
  }
  string returned_mapping() {
    return("Returned mapping.");
  }
  string empty_dir() {
    return("Pr�zdn� adres��.");
  }
  string returned_object() {
    return("Returned object.");
  }
  string returning_it() {
    return("Returning it.");
  }
  string has_find_dir_stat() {
    return("Has find_dir_stat().");
  }
  string returned_array() {
    return("Returned array.");
  }
  string file_on_mountpoint_path(string file, string path) {
    return(sprintf("Soubor %O je v cest� k mountpointu %O.",
		   file, path));
  }

  string error_disabling_module(string name, string bt) {
    return("Chyba p�i zastaven� modulu " + name +
	   (bt ? ":\n" + bt : "\n"));
  }
  string error_initializing_module_copy(string name, string bt) {
    return("Chyba p�i inicializaci instance modulu " + name +
	   (bt ? ":\n" + bt : "\n"));
  }
  string disable_nonexistant_module(string name) {
    return("Failed to disable module:\n"
	   "No module by that name: \"" +name + "\".\n");
  }
  string disable_module_failed(string name) {
    return("Failed to disable module \"" + name + "\".\n");
  }
  string enable_module_failed(string name, string bt) {
    return("Failed to enable the module " + name + ". Skipping." +
	   (bt ? "\n" + bt : "\n"));
  }

};


class _config_actions
{
  inherit .standard._config_actions; //Fallback

  constant all_memory_caches_flushed = "V�echny pam�ov� cache byly vymaz�ny.";

  constant font_test_string = "P��li� �lu�ou�k� k�� �p�l ��belsk� �dy.";
}


class _config_interface
{
  // config/low_describers.pike

  inherit .standard._config_interface; //Fallback

  string module_hint() {
    return "(Modul)";
  }
  string font_hint() {
    return "(Font)";
  }
  string location_hint() {
    return "(A location in the virtual filesystem)";
  }
  string file_hint() {
    return "(A filename in the real filesystem)";
  }
  string dir_hint() {
    return "(Adres�� v re�ln�m filesyst�mu)";
  }
  string float_hint() {
    return "(��slo)";
  }
  string int_hint() {
    return "(Cel� ��slo)";
  }
  string stringlist_hint() {
    return "(Seznam odd�len� ��rkami)";
  }
  string intlist_hint() {
    return "(Seznam cel�ch ��sel odd�len�ch ��rkami)";
  }
  string floatlist_hint() {
    return "(Seznam ��sel odd�len�ch ��rkami)";
  }
  string dirlist_hint() {
    return "(Seznam adres��� odd�len�ch ��rkami)";
  }
  string password_hint() {
    return "(Heslo)";
  }
  string ports_configured( int n )
  {
    if(!n) return "��dn� port nen� konfigurov�n";
    return _whatevers("port� konfigurov�no", n);
  }
  string unkown_variable_type() {
    return "Nezn�m� typ prom�nn�";
  }
  string lines( int n )
  {
    if(!n) return "pr�zdn�";
    if(n == 1) return "jeden ��dek";
    return _whatevers("��dk�", n);
  }


  string administration_interface() {
    return("Administra�n� rozhran�");
  }
  string admin_logged_on(string who, string from) {
    return("Administr�tor se p�ipojil jako "+who+" z " + from + ".\n");
  }


  string translate_cache_class( string classname )
  {
    return ([
      "supports":"supportdb",
      "fonts":"fonty",
      "hosts":"DNS",
    ])[ classname ] || classname;
  }

  constant name = "Jm�no";
  constant state = "Stav";

  constant features = "Vlastnost";
  constant module_disabled = "Zak�zan� moduly";
  constant all_modules = "V�echny moduly";

  constant disabled= "Zak�z�n";
  constant enabled = "<font color=&usr.fade4;>Povolen</font>";
  constant na      = "N/A";

  constant class_ = "T��da";
  constant entries = "Polo�ky";
  constant size = "Velikost";
  constant hits = "Hits";
  constant misses = "Misses";
  constant hitpct = "Hit%";

  constant reload = "Reload";
  constant empty = "Pr�zdn�";
  constant status = "Stav";
  constant sites =  "Servery";
  constant servers = "Servery";
  constant settings= "Nastaven�";
  constant usersettings= "U�ivatelsk� nastaven�";
  constant upgrade = "Upgrade";
  constant modules = "Moduly";
  constant globals = "Spole�n�";
  constant eventlog = "�urn�l";
  constant ports = "Porty";
  constant reverse = "Reverzn�";
  constant normal = "Norm�ln�";
  constant notice = "Pozn�mka";
  constant warning = "Upozorn�n�";
  constant error = "Chyba";
  constant actions = "Akce";
  constant manual = "Manu�l";
  constant clear_log = "Smazat �urn�l";


  constant debug_info = "Lad�c� info";
  constant welcome = "Ahoj";
  constant restart = "Restart";
  constant users = "U�ivatel�";
  constant shutdown = "Shutdown";
  constant home = "Start";
  constant configiftab = "Konfigura�n� rozhran�";

  constant create_user = "Vytvo�it u�ivatele";
  constant delete_user = "Smazat u�ivatele";

  constant delete = "Samazat";
  constant save = "Ulo�it";

  constant add_module = "P�idat modul";
  constant drop_module = "Odstranit modul";
  constant will_be_loaded_from = "Will be loaded from";

  constant maintenance = "�dr�ba";
  constant developer = "V�voj";

  constant create_new_site = "Vytvo�it server";
  constant with_template = "s pomoc� �ablony";
  constant site_pre_text = "";
  constant site_name = "Jm�no serveru";
  constant site_type = "Typ serveru";
  constant site_name_doc =
#"Jm�no mus� obsahovat pouze alfanumerick� znaky,
 nesm� kon�it na ~ a nesm� se jmenovat 'CVS',
 'Global Variables', 'global variables' a tak�
 nesm� obsahovat / .";
};

// Global useful words
constant ok = "Ok";
constant cancel = "Zru�it";
constant yes = "Ano";
constant no  = "Ne";
constant and = "a";
constant or = "nebo";
constant every = "v�dy";
constant since = "od";
constant next = "Dal��";
constant previous = "P�edchoz�";

constant actions = "Actions";
constant manual = "Manual";

string seconds(int n)
{
  if(n == 1) return "jedna sekunda";
  return _whatevers( "sekund", n );
}

string minutes(int n)
{
  if(n == 1) return "jedna minuta";
  return _whatevers( "minut", n );
}

string hours(int n)
{
  if(n == 1) return "jedna hodina";
  return _whatevers( "hodin", n );
}

string days(int n)
{
  if(n == 1) return "jeden den";
  return _whatevers( "dn�", n );
}


string module_doc_string(mixed module, string var, int long)
{
  return (::module_doc_string(module,var,long) ||
          RoxenLocale.standard.module_doc_string( module, var, long ));
}
