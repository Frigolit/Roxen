// This is a roxen module. Copyright 2000, Roxen IS

/* LDAP User authentification. Reads the directory and use it to
   authentificate users.

   Basic authentication names and passwords are mapped onto attributes
   in entries in preselected portions of an LDAP DSA.

   Uses 'uid' and 'userPassword' from entries with 'objectclass=person'.
   OR
   Tries to authenticate against ldap-server
   =====================================================================

  History:

  1998-03-05 v1.0	initial version
  1998-07-03 v1.1	added support for Protocols.LDAP module
  1998-07-03 v1.2	added authenticate against server
			(instead of using userpassword)
  			bonis@bonis.de
  1998-12-01 v1.3	added required attribute, more caching (bonis@bonis.de)
  1999-02-08 v1.4	more changes:
			 - incorporated 'user' type of authentication by Wim
			 - optimized
			 - removed support for old LDAP API
			 - added some templates
			 - changed perror() to werror()
			 - added logging of unsuccessful connections
			 - added checking of 'geteuid()' /not exists on NT/
  1999-07-26 v1.5	changed possibility of opened connection to the LDAP
			server - now disabled for 'user' access mode
  1999-08-07 v1.6	added more config options (i.e. attribute names)
			fields like uid,gid,gecos,homedir,shell now works
  1999-08-12 v1.7	added hack for pseudouser "A. Nonymous", now he isn't
			checked at all
  1999-08-14 v1.8a	- modified default attribute names to be compatible
			  with RFC2307
			- changed labels for 'Attribute names: ...' to
			  to more readable ' ... map'
  1999-08-18 v1.9	added catching errors in search op.
  1999-08-20 v1.10	- added logging all attempts of authenification
			- added id->misc[uid,gid,gecos,home,shell] update -now
			  works 'access as logged user'
			- added uid->name mapping
			! known bug: 1. unsuc. auth. is logged twice - status()
			  function returns incorrect values !!!
  1999-10-04 v1.11	- added "smart" checking of hashed passwords
			  (SHA, MD5 and CRYPT)
			- added config variable "userPassword map"
  1999-10-11 v1.12	- moved settings of 'pw' variable after checking it
  1999-12-14 v1.13	- fixed bug in required atrribute part
			- a litle optimalisation of cached values
  2000-02-13 v1.14	- added roaming auth mode
  2000-03-27 v1.15	- fixed settings of 'rpwd' for "roaming" mode
			  (Thanx Turbo Fredriksson!)
  2000-08-07 v1.19	- normalized and imported "roaming" from 1.3 tree 
  (more in cvs log)       ... and more

*/

constant cvs_version = "$Id: ldapuserauth.pike,v 1.23 2001/01/20 23:03:30 hop Exp $";
constant thread_safe=0;

#include <module.h>
inherit "module";
inherit "roxenlib";

//import Stdio;
//import Array;

#define LDAPAUTHDEBUG
#ifdef LDAPAUTHDEBUG
#define DEBUGLOG(s) werror("LDAPuserauth: "+s+"\n")
#else
#define DEBUGLOG(s)
#endif

#define LOG_ALL 1

/*
 * Globals
 */
object dir=0;
int dir_accesses=0, last_dir_access=0, succ=0, att=0, nouser=0;
mapping failed  = ([ ]);
mapping accesses = ([ ]);

mapping uids = ([ ]);
mapping gids = ([ ]);

int access_mode_is_user() {

  return !(query("CI_access_mode") == "user");
}

int access_mode_is_guest() {

  return !(query("CI_access_mode") == "guest");
}

int access_mode_is_roaming() {

  return !(query("CI_access_mode") == "roaming");
}

int access_mode_is_user_or_roaming() {

  return access_mode_is_user() & access_mode_is_roaming();
}


int access_mode_is_guest_or_roaming() {

  return access_mode_is_guest() & access_mode_is_roaming();
}


int default_uid() {

#if efun(geteuid)
  return(geteuid());
#else
  return(0);
#endif
}

/*
 * Object management and configuration variables definitions
 */

void create()
{
        defvar ("CI_access_mode","user","Access mode",
                   TYPE_STRING_LIST, "There are two generic mode:"
		   "<ol>"
		   "<li><b>user</b><br>"
                   "The user is authenticated against his own entry"
		   " in directory."
		   "<br>Optional you can specify attribute/value"
		   " pair must contained in."
		   "<li><b>guest</b><br>"
		   "The mode assume public access to the directory entries."
		   "<br>This mode is for testing purpose. It's not recommended"
		   " for real using."
		   "<li><b>roaming</b><br>"
		   "Mode designed to works with Netscape roaming LDAP"
		   " DIT tree.</ol>",
		({ "user", "guest", "roaming" }) );
        defvar ("CI_access_type","search","Access type",
                   TYPE_STRING_LIST, "Type of LDAP operation used "
		   "for authorization  checking."
		   "<br><i>Only 'search' type implemented, yet ;-)</i>",
		({ "search" }) );
		//({ "search", "compare" }) );

	// LDAP server:
        defvar ("CI_dir_server","ldap://localhost/??sub?(&(objectclass=person)(uid=%u%))","LDAP server: Location",
                   TYPE_STRING, "LDAP URL based information for connection"
		   " to directory server which maintains "
                   "the authentication information.<br>"
		   "LDAP URL form:<p>"
		   "ldap://hostname[:port]/base_DN[?[attribute_list][?[scope][?[filter][?extensions]]]]<p>"
		   "<i>More detailed info at <a href=\"http://community.roxen.com/developers/idocs/rfc/rfc2255.html\"> RFC 2255</a>.</i><br>"
		   "Notice:<i>"
		   " %u% will be replaced by username.</i>");

	// "user" access type
        defvar ("CI_required_attr","","LDAP server: Required attribute",
                   TYPE_STRING|VAR_MORE,
		   "Which attribute must be present to successfully"
		   " authenticate user (can be empty)"
		   "<br>Example: <i>memberOf</i>",
		   0,
		   access_mode_is_user_or_roaming
		   );
        defvar ("CI_required_value","","LDAP server: Required value",
                   TYPE_STRING|VAR_MORE,
		   "Which value must be in required attribute (can be empty)" 
		   "<br>Example: <i>cn=KISS-PEOPLE</i>",
		   0,
		   access_mode_is_user_or_roaming
		   );

	// "guest" access type
        defvar ("CI_dir_pwd","", "LDAP server: Directory user's password",
		    TYPE_STRING|VAR_MORE,
		    "This is the password used to authenticate "
		    "connection to directory.",
		   0,
		   access_mode_is_guest_or_roaming
		    );

	// "roaming" access type
        defvar ("CI_owner_attr","owner","LDAP server: Indirect DN attributename",
                   TYPE_STRING|VAR_MORE,
		   "Attribute name which contains DN for indirect authorization"
                   ". Value is used as DN for binding to the directory.",
		   0,
		   access_mode_is_roaming
		   );

	// Defaults:
        defvar ("CI_default_uid",default_uid(),"Defaults: User ID", TYPE_INT,
                   "Some modules require an user ID to work correctly. This is the "
                   "user ID which will be returned to such requests if the information "
                   "is not supplied by the directory search.");
        defvar ("CI_default_gid",
#ifdef __NT__
		0,
#else		
		getegid(),
#endif		
		"Defaults: Group ID", TYPE_INT,
                   "Same as User ID, only it refers rather to the group.");
        defvar ("CI_default_gecos", "", "Defaults: Gecos", TYPE_STRING,
                   "The default Gecos.");
        defvar ("CI_default_home","/", "Defaults: Home Directory", TYPE_DIR,
                   "It is possible to specify an user's home "
                   "directory. This is used if it's not provided.");
        defvar ("CI_default_shell","/bin/false", "Defaults: Shell", TYPE_STRING,
                   "The shell name for entries without own defined.");
        defvar ("CI_default_addname",0,"Defaults: Username add",TYPE_FLAG,
                   "Setting this will add username to path to default directory.");

	// Map
        defvar ("CI_default_attrname_upw", "userpassword",
		   "Map: User password map", TYPE_STRING,
                   "The mapping between passwd:password and LDAP.");
        defvar ("CI_default_attrname_uid", "uidnumber",
		   "Map: User ID map", TYPE_STRING,
                   "The mapping between passwd:uid and LDAP.");
        defvar ("CI_default_attrname_gid", "gidnumber",
		   "Map: Group ID map", TYPE_STRING,
                   "The mapping between passwd:gid and LDAP.");
        defvar ("CI_default_attrname_gecos", "gecos",
		   "Map: Gecos map", TYPE_STRING,
                   "The mapping between passwd:gecos and LDAP.");
        defvar ("CI_default_attrname_homedir", "homedirectory",
		   "Map: Home Directory map", TYPE_STRING,
                   "The mapping between passwd:homedir and LDAP.");
        defvar ("CI_default_attrname_shell", "loginshell",
		   "Map: Shell map", TYPE_STRING,
                   "The mapping between passwd:shell and LDAP.");

	// Etc.
        defvar ("CI_use_cache",1,"Cache entries", TYPE_FLAG,
                   "This flag defines whether the module will cache the directory "
                   "entries. Makes accesses faster, but changes in the directory will "
                   "not show immediately. <B>Recommended</B>.");
        defvar ("CI_close_dir",1,"Close the directory if not used",
		   TYPE_FLAG|VAR_MORE,
                   "Setting this will save one filedescriptor without a small "
                   "performance loss.",0,
		   access_mode_is_guest_or_roaming);
        defvar ("CI_timer",60,"Directory connection close timer",
		   TYPE_INT|VAR_MORE,
                   "The time after which the directory is closed",0,
                   lambda(){return !query("CI_close_dir") || access_mode_is_guest_or_roaming;});

}


void close_dir() {

    if (!query("CI_close_dir"))
	return;
    if( (time(1)-last_dir_access) > query("CI_timer") ) {
	dir->unbind();
	dir=0;
	DEBUGLOG("closing the directory");
	return;
    }
    call_out(close_dir,query("CI_timer"));
}

void open_dir(string u, string p) {
    mixed err;
    string binddn, bindpwd;
    string serverurl = query("CI_dir_server");
    mapping ldapurl;

    last_dir_access=time(1);
    dir_accesses++; //I count accesses here, since this is called before each
    if(dir)
	return;

    err = catch {
	dir = Protocols.LDAP.client(serverurl);
    };
    if (arrayp(err)) {
	werror ("LDAPauth: Couldn't open authentication directory!\n[Internal: "+err[0]+"]\n");
	if (objectp(dir)) {
	    werror("LDAPauth: directory interface replies: "+dir->error_string()+"\n");
	}
	else
	    werror("LDAPauth: unknown reason\n");
	werror ("LDAPauth: check the values in the configuration interface, and "
		"that the user\n\trunning the server has adequate permissions "
		"to the server\n");
	dir=0;
	return;
    }
    if(dir->error_number()) {
	werror ("LDAPauth: authentification error ["+dir->error_string()+"]\n");
	dir=0;
	return;
    }

    if(!access_mode_is_guest_or_roaming()) { // access type is "guest"/"roam."
        ldapurl = dir->parse_url(serverurl);
	bindpwd = query("CI_dir_pwd");
    } else {                      // access type is "user"
        ldapurl = dir->parse_url(replace(serverurl, "%u%", u));
	bindpwd = p;
    }
    binddn = zero_type(ldapurl["ext"]) ? "" : zero_type(ldapurl->ext["bindname"]) ? "" : ldapurl->ext->bindname;

    dir->bind(binddn, bindpwd);
    if(dir->error_number()) {
	werror ("LDAPauth: authentification error ["+dir->error_string()+"]\n");
	dir=0;
	return;
    }
    DEBUGLOG("directory successfully opened");
    if(query("CI_close_dir") && (query("CI_access_mode") != "user"))
	call_out(close_dir,query("CI_timer"));
}



/*
 * Statistics
 */

string status() {

    return ("<H2>Security info</H2>"
	   "Attempted authentications: "+att+"<BR>\n"
	   "Failed: "+(att-succ+nouser)+" ("+nouser+" because of wrong username)"
	   "<BR>\n"+
	   dir_accesses +" accesses to the directory were required.<BR>\n" +

	     "<p>"+
	     "<h3>Failure by host</h3>" +
	     Array.map(indices(failed), lambda(string s) {
	       return roxen->quick_ip_to_host(s) + ": "+failed[s]+"<br>\n";
	     }) * ""
	     //+ "<p>The database has "+ sizeof(users)+" entries"
#ifdef LOG_ALL
	     + "<p>"+
	     "<h3>Auth attempt by host</h3>" +
	     Array.map(indices(accesses), lambda(string s) {
	       return roxen->quick_ip_to_host(s) + ": "+accesses[s]->cnt+" ["+accesses[s]->name[0]+
		((sizeof(accesses[s]->name) > 1) ?
		  (Array.map(accesses[s]->name, lambda(string u) {
		    return (", "+u); }) * "") : "" ) + "]" +
		"<br>\n";
	     }) * ""
#endif
	   );

}


/*
 * Auth functions
 */

string get_attrval(mapping attrval, string attrname, string dflt) {

    return (zero_type(attrval[attrname]) ? dflt : attrval[attrname][0]);
}

array(string) userinfo (string u,mixed p) {
    array(string) dirinfo;
    object results;
    mixed err;
    mapping(string:array(string)) tmp, attrsav;

    DEBUGLOG ("userinfo ("+u+")");
    if (u == "A. Nonymous") {
      DEBUGLOG ("A. Nonymous pseudo user catched and filtered.");
      return 0;
    }

    if (query("CI_use_cache"))
	dirinfo=cache_lookup("ldapauthentries",u);
	if (dirinfo)
	    return dirinfo;

    open_dir(u, p);

    if (!dir) {
	werror ("LDAPauth: Returning 'user unknown'.\n");
	return 0;
    }

    if(query("CI_access_type") == "search") {
	string rpwd = "";
	string flt = dir->parse_url(query("CI_dir_server"))->filter||"";

	err = catch(results=dir->search(replace(flt, "%u%", u)));
	if (err || !objectp(results) || !results->num_entries()) {
	    DEBUGLOG ("no entry in directory, returning unknown");
	    if(access_mode_is_guest_or_roaming() && objectp(dir)) {
		catch(dir->unbind());
		dir=0;
	    }
	    return 0;
	}
	tmp=results->fetch();
	//DEBUGLOG(sprintf("userinfo: got %O",tmp));
	if(!access_mode_is_guest()) {	// mode is 'guest'
	    if(zero_type(tmp[query("CI_default_attrname_upw")]))
		werror("LDAPuserauth: WARNING: entry haven't '" + query("CI_default_attrname_upw") + "' attribute !\n");
	    else
		rpwd = tmp[query("CI_default_attrname_upw")][0];
	}
	if(!access_mode_is_user_or_roaming())	// mode is 'user'
	    rpwd = stringp(p) ? p : "{x-hop}*";
	if(!access_mode_is_roaming()) {	// mode is 'roaming'
	  // OK, now we'll try to bind ...
	  string binddn = get_attrval(tmp, query("CI_owner_attr"), "");
	  DEBUGLOG (sprintf("LDAPauth: indirect DN: [%s]\n", binddn));
	  if(!sizeof(binddn)) {
	    DEBUGLOG ("no value for indirect attribute, returning unknown");
	    return 0;
	  }
	  err = catch (dir->bind(binddn, p));
	  if (arrayp(err)) {
	    werror ("LDAPauth: Couldn't open authentication directory!\n[Internal: "+err[0]+"]\n");
	    if (objectp(dir)) {
	      werror("LDAPauth: directory interface replies: "+dir->error_string()+"\n");
	      catch(dir->unbind());
	    } else
	      werror("LDAPauth: unknown reason\n");
	    werror ("LDAPauth: check the values in the configuration interface,"
		    " and that the user\n\trunning the server has adequate"
		    " permissions to the server\n");
	    dir=0;
	    return 0;
	  }
	  if(dir->error_number()) {
	    werror ("LDAPauth: authentification error ["+dir->error_string()+"]\n");
	    dir=0;
	    return 0;
	  }
	  dir->set_scope(0);
	  dir->set_basedn(binddn);
	  //err = catch(results=dir->search(replace(query("CI_search_templ"), "%u%", u)));
	  err = catch(results=dir->search("objectclass=*")); // FIXME: modify
							      // to conf. int!
	  if (err || !objectp(results) || !results->num_entries()) {
	    DEBUGLOG ("no entry in directory, returning unknown");
	    if(objectp(dir)) {
	      catch(dir->unbind());
	      dir=0;
	    }
	    return 0;
	  }
	  tmp=results->fetch();
	}
	dirinfo= ({
		u, 			//tmp->uid[0],
		rpwd,
		get_attrval(tmp, query("CI_default_attrname_uid"), query("CI_default_uid")),
		get_attrval(tmp, query("CI_default_attrname_gid"), query("CI_default_gid")),
		get_attrval(tmp, query("CI_default_attrname_gecos"), query("CI_default_gecos")),
		query("CI_default_addname") ? query("CI_default_home")+u : get_attrval(tmp, query("CI_default_attrname_homedir"), ""),
		get_attrval(tmp, query("CI_default_attrname_shell"), query("CI_default_shell")),
		sizeof(query("CI_required_attr")) && !access_mode_is_user() && !zero_type(tmp[query("CI_required_attr")]) ? mkmapping(({query("CI_required_attr")}),tmp[query("CI_required_attr")]) : 0
	});
    } else {
	// Compare method is unimplemented, yet
    }
    #if 0
    if (query("CI_use_cache"))
	cache_set("ldapauthentries",u,dirinfo);
    #endif
    if(!access_mode_is_user()) { // Should be 'closedir' method?
      dir->unbind();
      dir=0;
    }
    if(!access_mode_is_roaming()) { // We must rebind connection
      //dir->bind(query("CI_dir_username"), query("CI_dir_pwd"));
      dir->bind(); //FIXME: quick hack
    }

    if(zero_type(uids[(string)dirinfo[2]]))
	uids = uids + ([ dirinfo[2] : ({ dirinfo[0] }) ]);
    else
	uids[dirinfo[2]] = uids[dirinfo[2]] + ({dirinfo[0]});
#if 0
    if(zero_type(gids[(string)dirinfo[3]]))
	gids = ([ dirinfo[3]:({dirinfo[0]}) ]);
    else
	gids[dirinfo[3]] = gids[dirinfo[3]] + ({dirinfo[0]});
#endif // FIXME: hacked - returns gidname = uidname !!!

    //DEBUGLOG(sprintf("Result: %O",dirinfo)-"\n");
    return dirinfo;
}

array(string) userlist() {

    //if (query("disable_userlist"))
    return ({});
}

string user_from_uid (int u) 
{

    if(!zero_type(uids[(string)u]))
	return(uids[(string)u][0]);
    return 0;
}

#if LOG_ALL
int chk_name(string x, string y) {

    return(x == y);
}
#endif

array|int auth (array(string) auth, object id)
{
    string u,p, pw;
    array(string) dirinfo;
    mixed attr,value;
    mixed err;

    att++;

    sscanf (auth[1],"%s:%s",u,p);

#if LOG_ALL
    if(!zero_type(accesses[id->remoteaddr]) && !zero_type(accesses[id->remoteaddr]["cnt"])) {
      accesses[id->remoteaddr]->cnt++;
      if(Array.search_array(accesses[id->remoteaddr]->name, chk_name, u) < 0)
	accesses[id->remoteaddr]->name = accesses[id->remoteaddr]->name + ({ u });
    } else
      accesses[id->remoteaddr] = (["cnt" : 1, "name":({ u })]);
#endif
    if (!p||!strlen(p)) {
	DEBUGLOG ("no password supplied by the user");
	failed[id->remoteaddr]++;
	roxen->quick_ip_to_host(id->remoteaddr);
	return ({0, auth[1], -1});
    }

    dirinfo=userinfo(u,p);
    if (!dirinfo||!sizeof(dirinfo)) {
	DEBUGLOG ("password check failed");
	DEBUGLOG ("no such user");
	nouser++;
	failed[id->remoteaddr]++;
	roxen->quick_ip_to_host(id->remoteaddr);
	return ({0,u,p});
    }
    pw = dirinfo[1];
    if(pw == "{x-hop}*")  // !!!! HACK
	pw = p;
    if(p != pw) {
	// Digests {CRYPT}, {SH1} and {MD5}
	int pok = 0;
	if (sizeof(pw) > 6)
	    switch (upper_case(pw[..4])) {
		case "{SHA}" :
		    pok = (pw[5..] == MIME.encode_base64(Crypto.sha()->update(p)->digest()));
		    DEBUGLOG ("Trying SHA digest ...");
		    break;

		case "{MD5}" :
		    pok = (pw[5..] == MIME.encode_base64(Crypto.md5()->update(p)->digest()));
		    DEBUGLOG ("Trying MD5 digest ...");
		    break;

		case "{CRYP" :
		    if (sizeof(pw) > 7 && pw[5..6] == "T}") {
			pok = !crypt(p,pw[7..]);
			DEBUGLOG ("Trying CRYPT digest ...");
		    }
		    break;
	    } // switch
	if (!pok) {
	    DEBUGLOG ("password check (" + pw + ", " + p + ") failed");
	    //fail++;
	    failed[id->remoteaddr]++;
	    roxen->quick_ip_to_host(id->remoteaddr);
	    return ({0,u,p});
	}
    }

    if(!access_mode_is_user()) {
	// Check for the Atributes
	if(sizeof(query("CI_required_attr"))) {
	    attr=query("CI_required_attr");
	    if (mappingp(dirinfo[7]) && dirinfo[7][attr]) {
		mixed d;
		d=dirinfo[7][attr];
		if(sizeof(query("CI_required_value"))) {
		    mixed temp;
		    int found=0;
		    value=query("CI_required_value");
		    foreach(d, mixed temp) {
			if (search(temp,value)!=-1)
			    found=1;
		    }
		    if (found) {
		        DEBUGLOG ("User "+u+" has value "+value+"\n");
		    } else {
			werror("LDAPuserauth: User "+u+" has not value "+value+"\n");
			failed[id->remoteaddr]++;
			roxen->quick_ip_to_host(id->remoteaddr);
			return ({0,u,p});
		    }
		}
	    } else {
		werror("LDAPuserauth: User "+u+" has no attr "+attr+"\n");
		failed[id->remoteaddr]++;
		roxen->quick_ip_to_host(id->remoteaddr);
		return ({0,u,p});
	    }

	}
    } // if access_mode_is_user

    // Its OK so save them
    if (query("CI_use_cache"))
	cache_set("ldapauthentries",u,dirinfo);

    id->misc->uid = dirinfo[2];
    id->misc->gid = dirinfo[3];
    id->misc->gecos = dirinfo[4];
    id->misc->home = dirinfo[5];
    id->misc->shell = dirinfo[6];

    DEBUGLOG (u+" positively recognized");
    succ++;
    return ({1,u,0});
}



/*
 * Registration and initialization
 */

constant module_type = MODULE_AUTH || MODULE_EXPERIMENTAL;
constant module_name = "LDAP directory authorization";
constant module_doc  = "Module for LDAP user authorization using "
  "Pike's internal Ldap directory interface.";

