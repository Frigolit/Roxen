/*
 * $Id: clientlayer.pike,v 1.44 1999/09/14 21:33:16 marcus Exp $
 *
 * A module for Roxen AutoMail, which provides functions for
 * clients.
 *
 * Johan Sch�n, August 1998
 */

#include <module.h>
inherit "module" : module;

constant cvs_version="$Id: clientlayer.pike,v 1.44 1999/09/14 21:33:16 marcus Exp $";
constant thread_safe=1;


/* Roxen module functions ----------------------------------- */

array register_module()
{
  return( ({ MODULE_PROVIDER,
	     "AutoMail Client Layer module",
	     "A module for Roxen AutoMail, which provides functions for "
             "client modules.",
	     0,
	     1 }) );
}

void create()
{
  defvar("maildir", "/home/js/AutoSite/mails/", "Mail storage directory", 
	 TYPE_DIR,
	 "This is the physical location of the root directory for all"
         " mail.");

  defvar("db_location", "mysql://auto:site@kopparorm/autosite",
	 "Database URL" ,TYPE_STRING,"");

  defvar("ldapurl", "", "LDAP base URL", TYPE_STRING,
	 "Enter an LDAP URL here to enable LDAP mode.<p>"
	 "Attributes that will be used:\n<pre>"
	 "dn\n"
         "inetOrgPerson.cn\n"
         "inetOrgPerson.ou\n"
         "inetOrgPerson.mail\n"
         "inetOrgPerson.mailalternateaddress\n"
         "inetOrgPerson.userpassword\n"
         "inetOrgPerson.uid\n"
         "domain.associatedomain\n"
	 "</pre>");
}

string query_provides()
{
  return "automail_clientlayer";
}


/* Global variables -------------------------------------------------- */

object sql = thread_local();
object ldapcon = thread_local();
Thread.Mutex lock = Thread.Mutex();
mapping (program:mapping(int:object)) object_cache = ([]);






/* (local) Utility functions   ---------------------------------------- */

string encode_binary( mixed what )
{
  return sql_quote( MIME.encode_base64( encode_value( what ), 1 ) );
}

mixed decode_binary( string what )
{
  if(!what) 
    return "";
  return decode_value( MIME.decode_base64( what ) );
}

mapping filter_headers( mapping from ) 
{
  mapping res = ([]);
  if(from->subject) res->subject = from->subject;
  if(from->from) res->from = from->from;
  if(from->to) res->to = from->to;
  if(from->date) res->date = from->date;
  if(from->cc) res->cc = from->cc;
  if(from->sender) res->sender = from->sender;
//   if(from->cc) res->cc = from->cc;
  return res;
}

string encode_headers( mapping from )
{
  string res="";
  foreach(indices(from), string f)
    res += f+": "+from[f]+"\n";
  return res;
}

string read_headers_from_fd( Stdio.File fd )
{
  fd->seek( 0 );
  string q = "", w;
  int pos;
  do {
    w = fd->read(1024);
    q+=w;
  } while(strlen(w)
	  && ((pos=search(q, "\r\n\r\n"))==-1)
	  && ((pos=search(q, "\n\n"))==-1));

  return q[..pos-1];
}

Sql.sql get_sql()
{
  return sql->get() || sql->set(Sql.sql(query("db_location")));
}

array(mapping(string:string)) squery(string fmt, mixed ... args)
{
  return get_sql()->query( sprintf(fmt, @args) );
}

string sql_insert_mapping(mapping m)
{
  string pre="",post="";
  foreach(indices(m), string q)
  {
    pre += q+",";
    post += "'"+quote((string)m[q])+"',";
  }
  return sprintf("( %s ) VALUES ( %s )", 
		 pre[..strlen(pre)-2], post[..strlen(post)-2]);
}


string quote(string what)
{
  return get_sql()->quote(what);
} 

function sql_quote = quote;

string hash_body_id(string body_id)
{
  body_id="0000"+body_id;
  int p=sizeof(body_id)-4;
  return body_id[p..p+1]+"/"+body_id[p+2..p+3];
}

Stdio.File load_body_get_obj(string body_id)
{
  Stdio.File o = Stdio.File();
  if(o->open( query("maildir")+"/"+hash_body_id(body_id)+"/"+body_id,"r" ))
    return o;
  return 0;
}

string get_unique_body_id()
{
  // FIXME: How is this table initialized?
  string id;
  object key = lock->lock(); /* Do this transaction locked. */
  squery("update message_body_id set last=last+1");
  id=squery("select last from message_body_id where 1=1")[0]->last;
  destruct(key);
  return id;
}

void delete_body(string body_id)
{
  rm(query("maildir")+"/"+hash_body_id(body_id)+"/"+body_id);
}

Stdio.File new_body( string body_id )
{
  string f = query("maildir")+"/"+hash_body_id(body_id)+"/"+body_id;
  mkdirhier(f);
  return Stdio.File(f, "rwct");
}

array stat_body(string body_id )
{
  return file_stat(query("maildir")+"/"+hash_body_id(body_id)+"/"+body_id);
}



/* LDAP Stuff ------------------------------------------------------ */

class LDAPURL {

  string scheme;
  string user, password;
  string hostport;
  string dn;
  array(string) attributes;
  string scope;
  string filter;
  mapping(string:string) critical_extensions = ([]);
  mapping(string:string) noncritical_extensions = ([]);

  void create(string u)
  {
    sscanf(u, "%[a-zA-Z]://%s", scheme, u);
    scheme = (scheme && lower_case(scheme)) || "ldap";
    if(2==sscanf(u, "%s/%s", hostport, u)) {
      array(string) p = u/"?";
      dn = p[0];
      if(sizeof(p)>1 && sizeof(p[1])) {
	attributes = p[1]/",";
      }
      if(sizeof(p)>2 && sizeof(p[2])) {
	scope = lower_case(p[2]);
      }
      if(sizeof(p)>3 && sizeof(p[3])) {
	filter = p[3];
      }
      if(sizeof(p)>4 && sizeof(p[4])) {
	foreach(p[4]/",", string ext) {
	  int c = 0;
	  string val = 0;
	  if(ext[..0]=="!") {
	    c++;
	    ext = ext[1..];
	  }
	  sscanf(ext, "%s=%s", ext, val);
	  if(c)
	    critical_extensions[lower_case(ext)] = val;
	  else
	    noncritical_extensions[lower_case(ext)] = val;
	}
      }
    } else hostport=u;
    if(2==sscanf(hostport, "%s@%s", user, hostport))
      sscanf(user, "%s:%s", user, password);
    if(!sizeof(hostport))
      hostport=0;
    if(dn && !sizeof(dn))
      dn=0;
  }

};


class LDAPConnection {

  static object ldap, ldap2;
  static string extra_filt;

  object find_all(string filt)
  {
    if(extra_filt)
      filt = "(&"+extra_filt+filt+")";
    object res = ldap->search(filt);
    if(res->num_entries()<1)
      return 0;
    return res;
  }

  mapping find_one(string filt)
  {
    object res = find_all(filt);
    return res && res->fetch();
  }

  array get_attrs(string dn, string ... attrs)
  {
    ldap2->set_basedn(dn);
    object r = ldap2->search(extra_filt||"(objectclass=*)"/*, 0, attrs*/);
    if(!r || r->num_entries()<1)
      return 0;
    mixed res = Array.map(rows(r->fetch(), attrs), lambda(array a) {
						     return a && a[0];
						   });
    return res;
  }

  void create(string url)
  {
    object u = LDAPURL(url);
    ldap = Protocols.LDAP.client(u->hostport||"localhost");
    ldap2 = Protocols.LDAP.client(u->hostport||"localhost");
    if(u->user) {
      ldap->bind(u->user, u->password);
      ldap2->bind(u->user, u->password);
    }
    if(u->dn)
      ldap->set_basedn(u->dn);
    if(u->scope)
      ldap->set_scope((["base":0,"one":1,"sub":2])[u->scope]);
    ldap2->set_scope(0);
    extra_filt = u->filter;
  }

};

object get_ldap()
{
  if(ldapcon->get())
    return ldapcon->get();
  string l = query("ldapurl");
  if(!l || !sizeof(l))
    return 0;
  return ldapcon->set(LDAPConnection(l));
}



/* Client Layer Abstraction ---------------------------------------- */

object get_cache_obj( mixed type, string|int id )
{
  type = (program)type;
  if(!object_cache[ type ])
    return 0;
  if(object_cache[ type ][ id ])
    return object_cache[ type ][ id ];
}

object get_any_obj(string|int id, mixed type, mixed ... moreargs)
{
  program ptype = (program)type;
  if(!object_cache[ ptype ])
    object_cache[ ptype ] = ([]);
  if( object_cache[ ptype ][ id ] )
  {
    object_cache[ ptype ][ id ]->create(id, @moreargs);
    return object_cache[ ptype ][ id ];
  }
  return object_cache[ ptype ][ id ] = type(id,@moreargs);
}

class Common
{
  string|int id;
  static int serial = time();
  final int get_serial()
  {
    return serial;
  }

  int modify()
  {
    serial++;
  }

  static mapping cached_misc = ([]);
  final static mixed misc_get(string table, string var)
  {
    // NOTE: var is truncated to 16 chars.
    var = sql_quote(var[..15]);

    if(!zero_type(cached_misc[var])) return cached_misc[var];
    array(mapping) a;
    a=squery("select qwerty from %s where id='%s' and variable='%s'", 
	     table, (string)id, var);
    if(sizeof(a))
      return cached_misc[var]=decode_binary( a[0]->qwerty );
    return cached_misc[var]=0;
  }

  final static mixed misc_set(string table, string name, mixed to)
  {
    modify();

    // NOTE: name is truncated to 16 chars.
    name = sql_quote( name[..15] );
    string enc = encode_binary( to );

    // FIXME: Should probably use UPDATE instead.
    squery("delete from %s where id=%s and variable='%s'", table, 
	   (string)id, name);
    squery("insert into %s values (%s,'%s','%s')", table, 
	   (string)id, name, enc);
    return cached_misc[name]=to;
  }
}

class Mail
{
  inherit Common;
  inherit MIME.Message;
  string message_id;
  object user;
  object mailbox;

  int _size;
  mapping _dh;
  mapping _headers;
  static multiset _flags;
  static string _incoming_date;

  void modify()
  {
    if(mailbox)
      mailbox->modify();
    ::modify();
  }

  mixed change( MIME.Message to )
  {
    _size=0;
    new_body( headers()->body_id )->write( (string)to );
    squery("update messages set sender='%s', "
	   "subject='%s', headers='%s' WHERE id=%s",
	   sql_quote(to->headers->from||""),
	   sql_quote(to->headers->subject||""),
	   sql_quote(encode_headers(filter_headers(to->headers))),
	   message_id);
    
    foreach(user->mailboxes(), object m )
    {
      foreach(m->mail(), object q)
	if(q->message_id == message_id)
	{
	  q->_headers = 0;
	  q->_dh = 0;
	  q->modify();
	}
    }
  }

  mixed get(string var)
  {
    return misc_get("mail_misc", var);
  }

  mixed set(string name, mixed to)
  {
    return misc_set("mail_misc", name, to);
  }

  Stdio.File body_fd()
  {
    return load_body_get_obj( headers()->body_id );
  }

  string body()
  {
    return body_fd()->read();
  }

  string read_headers()
  {
    return read_headers_from_fd(body_fd());
  }
  
  int get_size( )
  {
    if(_size) return _size;
    return (_size = body_fd()->stat()[ 1 ]);
  }

  mapping decoded_headers(int|void force)
  {
    if(_dh && !force)
      return _dh;
    mapping heads = copy_value(headers(force));
    foreach(indices(heads), string w)
    {
      array(string) fusk0 = heads[w]/"=?";
      heads[w]=fusk0[0];
      foreach(fusk0[1..], string fusk)
      {
	string fusk2;
	string p1,p2,p3;
	if(sscanf(fusk, "%[^?]?%1s?%[^?]%s", p1,p2,p3, fusk) == 4)
	{
	  werror("dw: =?"+p1+"?"+p2+"?"+p3+"?=\n");
	  heads[w] += MIME.decode_word("=?"+p1+"?"+p2+"?"+p3+"?=")[0];
	}
	sscanf(fusk, "?=%s", fusk);
	heads[w] += fusk;
      }
    }
    return _dh=heads;
  }

  mapping headers(int|void force)
  {
    if(!_headers || force)
    {
      mapping h = get_mail_headers( message_id );
      _incoming_date = h->incoming_date;
      return _headers = MIME.parse_headers( h[ "headers" ] )[0] | h;
    }
    return _headers;
  }

  string incoming_date(int|void force)
  {
    if (!_incoming_date || force) {
      headers(force);
    }
    return _incoming_date;
  }

  multiset(string) flags(int|void force)
  {
    if(!_flags || force)
      return _flags = get_mail_flags( id );
    return _flags;
  }

  void set_flag(string name)
  {
    if(!flags()[name])
    {
      if(name == "read")
	if(mailbox->_unread != -1)
	  mailbox->_unread--;
      modify();
      _flags = 0;
      set_mail_flag( id, name );
    }
  }

  void clear_flag(string name)
  {
    if(flags()[name])
    {
      if(name == "read")
	if(mailbox->_unread != -1)
	  mailbox->_unread++;
      modify();
      _flags = 0;
      delete_mail_flag( id, name );
    }
  }

  void delete()
  {
    mailbox->remove_mail(  this_object() );
  }

  void create(string i, string m, object mb)
  {
    user = mb->user;
    id = (string)i;
    message_id = (string)m;
    mailbox = mb;
  }
}

class Mailbox
{
  inherit MIME.Message;
  inherit Common;
  static array _mail = 0;

  object user;
  string name;
  int _unread = -1;

  mixed get(string var)
  {
    return misc_get("mailbox_misc", var);
  }

  mixed set(string name, mixed to)
  {
    return misc_set("mailbox_misc", name, to);
  }

  void modify()
  {
    //  _unread = -1;
    if(user)
      user->modify();
    ::modify();
  }

  int num_unread()
  {
    if(_unread != -1)
      return _unread;
    return _unread = (sizeof(mail()->flags()->read-({1})));
  }

  void force_remove_mail(Mail mm)
  {
    _mail -= ({ mm }); // optimization, for speed...
//     _mail = 0; // No optimization, for safety...
    _unread = -1;
    modify( );
    array st = stat_body(mm->headers()->body_id);
    int sz = st && st[1]>0 && st[1];
    remove_mailbox_from_mail( mm->id, mm->message_id );
    user->deallocate_quota(sz);
    destruct( mm );
  }

  void remove_mail(Mail mm)
  {
    if(search(mail()->message_id, mm->message_id) != -1)
      force_remove_mail( mm );
  }

  Mail add_mail(Mail mm, int|void nocopy)
  {
    if(search(mail()->message_id, mm->message_id) == -1)
    {
      _mail = 0;
      _unread = -1;
      modify();
      add_mailbox_to_mail( mm->message_id, id );
      foreach(mail(), Mail m)
	if(m->message_id == mm->message_id)
	{
	  if(!nocopy)
	    foreach(indices(mm->flags()), string f)
	      m->set_flag( f );
	  return m;
	}
      error("Added message could not be found in list of messages.\n");
    }
    return mm;
  }

  int rename(string to)
  {
    name=0;
    rename_mailbox( id, to );
  }
    
  void delete()
  {
    foreach(mail(), object m)
      force_remove_mail( m );
    modify();
    user->_mboxes = 0;
    delete_mailbox( id );
    destruct(this_object());
  }
  
  string query_name(int|void force)
  {
    if(force) name=0;
    return name||(name=get_mailbox_name( id ));
  }

  Mail get_mail_by_id( string id )
  {
    Mail m;

    if(m = get_cache_obj( Mail, id ))
      return m;

    foreach(mail(), m)
      if(m->id == id) 
	return m;
  }
  
  array(Mail) mail(int|void force)
  {
    if(!force && _mail)
      return _mail;
    mapping q = list_mail( id );
    _mail = ({ });
    foreach(indices(q), string w)
      _mail += ({ get_any_obj( (string)w, Mail, 
			       (string)q[w], this_object()) });
    
    sort((array(int))_mail->message_id, _mail);

    return _mail;
  }


  Mail low_create_mail( string bodyid, mapping headers )
  {
    /* This could be easier.. :-) */

    // 0> Check quota.
    array st = stat_body(bodyid);
    int sz = st && (st[1]>0) && st[1];

    if (!user->check_quota(sz)) {
      // Out of quota.
      return 0;
    }

    // 1> Generate the db row for the 'messages' table.
    mapping row = ([
      "sender":headers->from,
      "subject":headers->subject,
      "body_id":bodyid,
      "headers":encode_headers(filter_headers(headers)),
    ]);

    // 2> Insert the row in the database, and get a new message id.
    string mid = create_message( row );
    
    // 3> Insert the message in this mailbox using the 'mail' table.
    string lmid = add_mailbox_to_mail( mid, id );
    
    // 4> Zap the cache.
    //     _mail = 0;
    _unread = -1;
    modify();

    // 5> Allocate quota.
    user->allocate_quota(sz);

    if(!_mail) 
    {
      foreach(mail(), Mail m)
	if((string)m->message_id == (string)mid)
	  return m;
      // Oups. This should not happend. :-)
      error(sprintf("Failed to find newly created message %s for mbox %s!\n", 
		    mid,(string)id));
    }

    Mail m;
    _mail += ({ m = get_any_obj(lmid, Mail, mid, this_object()) });
//     if(!object_cache[ (program)Mail ])
//       object_cache[ (program)Mail ] = ([ lmid:m ]);
//     else
//       object_cache[ (program)Mail ][ lmid ] = m;
    return m;
  }

  Mail create_mail_from_fd( Stdio.File fd )
  {
    // Check quota.
    array st = fd->stat();
    if (st && (st[1] > 0) && !user->check_quota(st[1])) {
      // Out of quota.
      return 0;
    }

    string foo = read_headers_from_fd( fd );
    mapping headers = MIME.parse_headers( foo )[0];
    string bodyid = get_unique_body_id();
    fd->seek( 0 );
    int amount;
    Stdio.File f = new_body( bodyid );
    do 
    {
      foo = fd->read( 8192 );
      amount += sizeof(foo);
      if( f->write( foo ) != strlen(foo) ) {
	f->close();
	delete_body(bodyid);
	error("Failed to write body.\n");
      }
    } while(strlen(foo) == 8192);
    f->close();
    return low_create_mail( bodyid, headers );
  }

  Mail create_mail_from_data( string data )
  {
    if (!user->check_quota(sizeof(data))) {
      // Out of quota.
      return 0;
    }
    return create_mail( MIME.Message( data, 0, 0 ) );
  }

  Mail create_mail( MIME.Message m )
  {
    string data = (string)m;
    if (!user->check_quota(sizeof(data))) {
      // Out of quota.
      return 0;
    }
    string bodyid = get_unique_body_id();
    object f = new_body( bodyid );
    if(f->write(data) != strlen(data))
      error("Failed to write body.\n");
    return low_create_mail( bodyid, m->headers );
  }

  void create(int i, object u, string n)
  {
    id = i;
    if(user != u)
      modify();
    user = u;
    if(name != n)
      modify();
    name = n;
  }
}

class User
{
  inherit Common;
  array _mboxes;

  static Mailbox create_mailbox( string name )
  {
    _mboxes = 0;
    modify();
    return Mailbox( create_user_mailbox( id, name ), this_object(), name );
  }

  mixed get(string var)
  {
    return misc_get("user_misc", var);
  }

  mixed set(string name, mixed to)
  {
    return misc_set("user_misc", name, to);
  }

  string query_name(int|void force)
  {
    return get_user_realname( id );
  }

  string query_organization()
  {
    return get_organization(id);
  }

  int query_customer_id()
  {
    /* Not supported in LDAP mode... */
    /* Affects FAX and SMS */
    return get_customer(id);
  }
  
  /* Quota stuff */

  int query_quota()
  {
    return get_user_quota(id);
  }

  int query_usage()
  {
    return get("quota_usage");
  }

  void set_usage(int usage)
  {
    set("quota_usage", usage);
  }

  int check_quota(int amount)
  {
    int q = query_quota();
    if (!q) {
      // No quota at all.
      return 0;
    }
    return(query_usage() + amount <= q);
  }

  int allocate_quota(int amount)
  {
    int u = query_usage() + amount;

    if (u < 0) {
      // No negative usage...
      u = 0;
    }

    set_usage(u);

    return(u <= query_quota());
  }

  int deallocate_quota(int amount)
  {
    return allocate_quota(-amount);
  }

  /* Mailbox stuff */

  array(Mailbox) mailboxes(int|void force)
  {
    if(!force && _mboxes)
      return _mboxes;
    mapping m = list_mailboxes(id);
    array a = values(m), b = indices(m);
    for(int i=0; i<sizeof(a); i++)
      a[i] = get_any_obj( a[i], Mailbox, this_object(), b[i] );
    return _mboxes = a;
  }

  void delete()
  {
    foreach(mailboxes(1),object(Mailbox) mb)
      mb->delete();
    delete_user(id);
    destruct(this_object());
  }

  Mailbox get_incoming()
  {
    return get_or_create_mailbox( "incoming" );
  }

  Mailbox get_drafts()
  {
    return get_or_create_mailbox( "drafts" );
  }

  Mailbox get_mailbox( string name )
  {
    foreach(mailboxes(), Mailbox m )
      if( lower_case(m->query_name()) == lower_case(name) ) 
	return m;
  }

  Mailbox get_or_create_mailbox( string name )
  {
    if(Mailbox m = get_mailbox(name))
      return m;
    return create_mailbox( name );
  }

  void create(int|string _id)
  {
    id = _id;
  }
}

User get_user( string username_at_host, string password )
{
  int|string id;
  id = authenticate_user( username_at_host, password );
  if(!id) return 0;
  return get_any_obj( id, User );
}

User get_user_from_address( string username_at_host )
{
  int|string id;
  id = find_user( username_at_host );
  if(!id) return 0;
  return get_any_obj( id, User );
}






/* Low level client layer functions ---------------------------------- */


string get_addr(string addr)
{
  array a = MIME.tokenize(addr);

  int i;

  if ((i = search(a, '<')) != -1) {
    int j = search(a, '>', i);

    if (j != -1) {
      a = a[i+1..j-1];
    } else {
      // Mismatch, no '>'.
      a = a[i+1..];
    }
  }

  for(i = 0; i < sizeof(a); i++) {
    if (intp(a[i])) {
      if (a[i] == '@') {
	a[i] = "@";
      } else {
	a[i] = "";
      }
    }
  }
  return(a*"");
}

multiset(string) list_domains()
{
  multiset(string) res;
  object l = get_ldap();
  if(l) {
    object r = l->find_all("(objectclass=domain)");
    array(string) dns = ({});
    if(r)
      for(int i=0; i<r->num_entries(); i++)
	dns += r->fetch(i+1)->associateddomain;
    res=mkmultiset(dns);
  }
  else
    res=aggregate_multiset(@squery("select distinct domain from dns")->domain);
  return res;
}

string get_user_realname(int|string user_id)
{
  if(stringp(user_id)) {
    object l = get_ldap();
    return l && (l->get_attrs(user_id, "cn")||({0}))[0];
  }
  array a = squery("select realname from users where id='%d'",
		   user_id);
  if(!sizeof(a))
    return 0;
  else
    return a[0]->realname;
}

string get_organization(int|string user_id)
{
  if(stringp(user_id)) {
    object l = get_ldap();
    return l && (l->get_attrs(user_id, "ou")||({0}))[0];
  }
  array a = squery("select customers.name from users,customers where users.id='%d'" 
		   " and users.customer_id=customers.id", user_id);
  if(!sizeof(a))
    return 0;
  else
    return a[0]->name;
}

int get_user_quota(int|string user_id)
{
  if(stringp(user_id)) {
    object l = get_ldap();
    // NOTE: According to the LDAP spec zero quota means unlimited.
    return l && ((int)((l->get_attrs(user_id, "mailQuota")||({0}))[0]) ||
		 0x7fffffff);
  }
  array a = squery("select quota from users where id='%d'", user_id);
  if(!sizeof(a))
    return 0;
  else
    return ((int)(a[0]->quota)) || 0x7fffffff;
}

int get_customer(int|string user_id)
{
  /* Not supported in LDAP mode... */
  if(stringp(user_id))
    return 0;
  array a = squery("select customer_id from users where id='%d'",user_id);
  if(!sizeof(a))
    return 0;
  else
    return (int)a[0]->customer_id;
}

int|string find_user( string username_at_host )
{
  catch {
    string user,domain;
    if(search(username_at_host,"@")!=-1)
      [user,domain]=get_addr(lower_case(username_at_host))/"@";
    else if(search(username_at_host,"*")!=-1)
      [user,domain]=get_addr(lower_case(username_at_host))/"*";

    object l = get_ldap();

    if(l) {
      object r = l->find_all("(|(mail="+username_at_host+
			     ")(mailalternateaddress="+username_at_host+"))");
      if(!r || r->num_entries()<1)
	return 0;
      if(r->num_entries()>1) error("Ambigious user list.\n");
      return r->fetch()->dn[0];
    }

    int customer_id;
    array a = squery("select customer_id from dns where domain='%s' "
		     " group by customer_id", domain);
    if(!sizeof(a)) return 0;
    customer_id=(int)a[0]->customer_id;
    array a = squery("select id from users where username='%s' and"
		     " customer_id='%d'", user,customer_id);
    if(!sizeof(a)) return 0;
    if(sizeof(a)>1) error("Ambigious user list.\n");
    return (int)a[0]->id;
  };
}

int delete_user(int|string user_id)
{
  if(intp(user_id))
    squery("delete from users where id='%d'",user_id);
  squery("delete from user_misc where id='%s'",(string)user_id);
}


int|string authenticate_user(string username_at_host, string passwordcleartext)
{
  object l = get_ldap();

  if(l) {
    object r = l->find_all("(&(uid="+username_at_host+")(userpassword={SHA}"+
			   MIME.encode_base64(Crypto.sha()->
					      update(passwordcleartext)->
					      digest(), 1)+"))");
    if(!r || r->num_entries()<1)
      return 0;
    if(r->num_entries()>1) error("Ambigious user list.\n");
    return r->fetch()->dn[0];
  }

  int id = find_user( username_at_host );
  if(!id) return 0;
  array a=squery("select password from users where id='%d'", id);
  if(!sizeof(a))
    return 0;
  return (crypt(passwordcleartext, a[0]->password)) && id;
}

mapping(string:int) list_mailboxes(int|string user)
{
  array a=squery("select id,name from mailboxes where user_id='%s'",(string)user);
  return mkmapping( column( a, "name" ), (array(int))column(a, "id" ) );
//   mapping mailboxes=([]);
//   foreach(a, mapping row)
//     mailboxes[row->name]=(int)row->id;
//   return mailboxes;
}

mapping(string:string) list_mail(int mailbox_id)
{
  array a=squery("select m.id as m,l.id as l from mail as l, messages as m"
		 " where l.mailbox_id='%d' and m.id=l.message_id"
		 " order by m.id",
		 mailbox_id);
  return mkmapping(column( a, "l" ), column( a, "m" ));
}

mapping(string:mixed) get_mail(string message_id)
{
  return get_mail_headers( message_id );
}

mapping(string:mixed) get_mail_headers(string message_id)
{
//   array a=query("select message_id from mail where id='"+message_id+"'");
//   if(!sizeof(a))
//     return 0;
  array a = squery("select * from messages where id='%s'",message_id);
  if(!sizeof(a))
    return 0;
  return a[0];
}

int update_message_refcount(string message_id, int deltacount)
{
  array a=squery("select refcount,body_id from messages where id='%s'", message_id);
  if(!a||!sizeof(a))
    return 0;
  int refcount=(int)a[0]->refcount + deltacount;
  if(refcount <= 0)
  {
    squery("delete from messages where id='%s'",message_id);
    delete_body(a[0]->body_id);
  }
  else
    squery("update messages set refcount='%d' where id=%s",
	   refcount, message_id);
  return 1;
}

int delete_mail(string mail_id)
{
  array a=squery("select message_id from mail where id='%s'", mail_id);
  if(!sizeof(a))
    return 0;
  string message_id = a[0]->message_id;
  squery("delete from mail where id='%s'",mail_id);
  a=squery("select refcount,body_id from messages where id='%s'",message_id);
  if(!a||!sizeof(a))
    return 0;
  if(!update_message_refcount(message_id,-1))
    return 0;
  return 1;
}

int create_user_mailbox(int|string user, string mailbox)
{
  squery("insert into mailboxes values(NULL,'%s','%s')",
	 (string)user,sql_quote(mailbox));
  return (int)get_sql()->master_sql->insert_id();
}

string create_message(mapping mess)
{
  get_sql()->query("insert into messages "+sql_insert_mapping( mess ));
  return (string)get_sql()->master_sql->insert_id();
}

string get_mailbox_name(int mailbox_id)
{
  array a=squery("select name from mailboxes where id='%d'",mailbox_id);
  if(!sizeof(a)) return 0;
  return a[0]->name;
}

int delete_mailbox(int mailbox_id)
{
  squery("delete from mailboxes where id='%d'", mailbox_id);
  squery("delete from mailbox_misc where id='%d'", mailbox_id);
  foreach(indices(list_mail(mailbox_id)), string mail_id)
    delete_mail(mail_id);
  return 1;
}

int rename_mailbox(int mailbox_id, string newname)
{
  squery("update mailboxes set name='%s' where id='%d'", newname, mailbox_id);
  return 1;
}

int remove_mailbox_from_mail(string mail_id, string message_id)
{
  squery("delete from mail_misc where id='%s'", mail_id);
  squery("delete from flags where mail_id='%s'", mail_id);
  squery("delete from mail where id='%s'", mail_id);
  update_message_refcount( message_id, -1 );
}

string add_mailbox_to_mail(string message_id, int mailbox_id)
{
//   array a=query("select message_id from mail where id='"+mail_id+"'");
//   if(!sizeof(a))
//     return 0;
//   string message_id=a[0]->message_id;
  squery("insert into mail values(NULL,'%d','%s')",mailbox_id,message_id);
  string res = (string)get_sql()->master_sql->insert_id();
  update_message_refcount(message_id,1);
  return res;
}

void set_mail_flag(string mail_id, string flag)
{
  squery("insert into flags values('%s','%s')",mail_id,flag);
}

void delete_mail_flag(string mail_id, string flag)
{
  squery("delete from flags where mail_id='%s' and name='%s'",mail_id,flag);
}

void add_charge_to(string what, int customer_id)
{
  int charge=0;
  array a=squery("select charge from customer_charges where type='%s' "
		 "and customer_id=%d", what,  customer_id);
  if(!sizeof(a))
    charge=0;
  else
     charge=(int)(a[0]->charge);
  
  charge++;
  squery("replace into customer_charges (charge, customer_id, type) values(%d,%d,'%s')",
	 charge, customer_id, what);
}
  
multiset get_mail_flags(string mail_id)
{
  array a=squery("select name from flags where mail_id='%s'",mail_id);;
  if(!a) return (<>);
  multiset flags=(<>);
  foreach(a, mapping row)
    flags[row->name]=1;
  return flags;
}
