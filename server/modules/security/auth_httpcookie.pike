constant cvs_version =
  "$Id: auth_httpcookie.pike,v 1.1 2001/01/19 16:35:47 per Exp $";
inherit AuthModule;
inherit "module";

#define COOKIE "_roxen_cookie_auth"

constant name = "httpcookie";

//<locale-token project="mod_auth_httpcookie">_</locale-token>
#define _(X,Y)	_DEF_LOCALE("mod_auth_httpcookie",X,Y)

#include <module.h>

LocaleString module_name_locale =
  _(0,"HTTP Cookie authentication");

LocaleString module_doc_locale =
  _(0,"Authenticate users using a cookie.");

static User low_authenticate( RequestID id,
			      string user, string password,
			      UserDB db )
{
  if( User u = db->find_user( user ) )
    if( u->password_authenticate( password ) )
      return u;
}

static Sql.Sql sql;
static string table;

static string encode_pw(string p)
{
  return Gmp.mpz( ~p, 256 )->digits( 9 );
}

static string decode_pw( string p )
{
  return ~Gmp.mpz( p, 9 )->digits( 256 );
}

static array(string) low_lookup_cookie( string cookie )
{
  array r = 
    sql->query( "SELECT name,password FROM "+
		table+" WHERE cookie=%s", cookie );
  if( !sizeof( r ) )
    return ({0,0});
  return ({ decode_pw(r[0]->password), decode_pw( r[0]->name ) });
}

static mapping(string:array(string)) cookies = ([]);
static array(string) lookup_cookie( string cookie )
{
  if( cookies[ cookie ] )
    return cookies[ cookie ];
  cookies[ cookie ] = low_lookup_cookie( cookie );
  if( !cookies[cookie][0] )
    return m_delete( cookies, cookie );
  return cookies[cookie];
}

static string create_cookie( string u, string p )
{
  int i = (((hash(u) << 32) | hash(p)) << 32) | hash(u+p);
  string c = i->digits(16);
  catch(sql->query( "INSERT INTO "+table+" "
		    "(cookie,name,password) VALUES "
		    "(%s,%s,%s)", c, encode_pw(u), encode_pw(p) ));
  return c;
}

User authenticate( RequestID id, UserDB db )
//! Try to authenticate the request with users from the specified user
//! database. If no @[db] is specified, all datbases in the current
//! configuration are searched in order, then the configuration user
//! database.
//!
//! The return value is the autenticated user.
{
  string password;
  string user;

  if( !id->cookies[ COOKIE ] )
    return 0;

  [password,user] = lookup_cookie( id->cookies[ COOKIE ] );

  if( !user || !password )
    return 0;

  User res;
  if( !db )
  {
    foreach( id->conf->user_databases(), UserDB db )
      if( res = low_authenticate( id, user, password, db ) )
	return res;
    Roxen.remove_cookie( id, COOKIE, "", 0, "/" );
    return 0;
  }
  res = low_authenticate( id, user, password, db );
  if( !res )
    Roxen.remove_cookie( id, COOKIE, "", 0, "/" );
  return res;
}


mapping authenticate_throw( RequestID id, string realm, UserDB db )
//! Returns a reply mapping, similar to @[Roxen.http_rxml_reply] with
//! friends. If no @[db] is specified,  all datbases in the current
//! configuration are searched in order, then the configuration user
//! database.
{
  string u, p;
  if( (u=id->variables->_cookie_username) &&
      (p=id->variables->_cookie_password) )
  {
    Roxen.set_cookie( id, COOKIE, create_cookie( u, p ), -1, 0, "/");
    return Roxen.http_redirect( id->not_query+"?"+
				"netscape=needsthis&"+id->query, id );
  }

  return Roxen.http_rxml_answer(
    replace( query("user_form"),
	     ({"PWINPUT", "UNINPUT", "REALM"}),
	     ({
	       "<input size=16 type='password' name='_cookie_password' />",
	       "<input size=16 name='_cookie_username' />",
	       realm
	     }) ), id );
}

void start()
{
  sql = get_my_sql();
  table = get_my_table(
    "cookie varchar(40) PRIMARY KEY NOT NULL, "
    "password varchar(40) NOT NULL, "
    "name varchar(40) NOT NULL"
  );
}

void create()
{
  defvar( "user_form", Variable.Text(
#"
<title>Authentication required for REALM</title>
<body alink=\"#000000\" bgcolor=\"#ffffff\" text=\"#000000\">
 <form method='POST'>
  Username: UNINPUT<br />
  Password: PWINPUT<br />
           <input type=submit value=' Ok ' />
</form></body>",0,
   _(0,"User form"),_(0,"The user/password request form shown to the user"))); 
}
