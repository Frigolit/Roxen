/* This is -*- pike -*- code */
/* Standard roxen module header -------------------------------- */
#include <module.h>
inherit "module";
inherit "roxenlib";
inherit Regexp : regexp;

constant cvs_version = 
"$Id: mailtags.pike,v 1.12 1998/09/16 18:53:23 per Exp $";

constant thread_safe = 1;


/* Some defines to cheer up our day ---------------------------- */

#define UID id->misc->_automail_user

#ifdef DEBUG
# undef DEBUG
#endif

#ifdef MODULE_DEBUG
# define DEBUG(X) if(debug) werror X ;
#else
# define DEBUG(X) 
#endif

/* Prototypes ----------------------------------------------------- */
#define WANT_CLIENTINIT
#include "clientlayer.h"


/* Globals ---------------------------------------------------------*/

static MIME.Message mymesg = MIME.Message();
static roxen.Configuration conf;
static int debug, secure;

/* Roxen module glue ---------------------------------------------- */
/* These functions are arranged in calling order. ----------------- */

void create()
{
  defvar("debug", 0, "Debug", TYPE_FLAG, 
	 "If this flag is set, debugging output might be added for some"
	 " tags. Also, more sanity checks will be done");

  defvar("security_level", "high", "Security level", 
	 TYPE_STRING_LIST|VAR_MORE,
	 "The level of security verification to do.<p>"
	 "high:  All checks. It should be impossible to read mail"
	 " that is not yours, same goes for list of mail etc.<p>"
	 "mail: Only the ownership of mail will be checked.<p>"
	 "low: Only checks that will not generate extra CVS queries"
	 " will be done. This saves CPU, but the cost is high. A smart and"
	 " resourcefull user could read all mail.",
	 ({ "high", "mail", "low"}));

  regexp::create("^(.*)((http://|https://|ftp:/|news:|wais://|mailto:"
		 "|telnet:)[^ \n\t\012\014\"<>|\\\\]*[^ \n\t\012\014"
		 "\"<>|\\\\.,(){}?'`*])");
}

array register_module()
{
  return ({ MODULE_PARSER|MODULE_PROVIDER, "Automail HTML client",
	    "This module adds quite a few new tags for Automail email "
	    "handling. This module talks to the AutoMail client layer module",
	    0,1 });
}

mapping query_tag_callers()
{
  return common_callers(  "tag_" );
}

mapping query_container_callers()
{
  return common_callers(  "container_" );
}

string query_provides()
{
  return "automail_htmlmail";
}


void start(int q, roxen.Configuration c)
{
  if(!c)
  {
    report_debug("start called without configuration\n");
    return;
  }  
  conf = c;
  report_notice("AutoMail HTML Client added to the '"+c->query_name()+
		"' configuration.\n");

  if(!init_clientlayer( c ))
    report_error("AutoMail HTML Client init failed!\n");

  debug = query("debug");
  
  if(query("security_level") == "high")
    secure=2;
  else if(query("security_level") == "mail")
    secure=1;
  else
    secure=0;
}

/* Utility functions ---------------------------------------------- */

// For multipart/alternative
static int type_score( MIME.Message m )
{
  return (m->type == "text") + ((m->subtype == "html")*2) + 
         (m->type=="multipart")*2;
}

// for multipart/related
static mixed internal_odd_tag_href(string t, mapping args, 
				   string url, string pp )
{
  int pno;
  if(args->href && sscanf(args->href, "cid:part%d", pno))
  {
    args->href = replace(url, "#part#", pp+"/"+(string)pno);
    return ({ make_tag(t, args ) });
  }
}

// for multipart/related
static mixed internal_odd_tag_src(string t, mapping args, 
				  string url, string pp )
{
  int pno;
  if(args->src && sscanf(args->src, "cid:part%d", pno))
  {
    args->src = replace(url, "#part#", pp+"/"+(string)pno);
    return ({ make_tag(t, args ) });
  }
}

// for text/enriched
class Tag
{
  string tn;

  string `()(string t, mapping m, string c)
  {
    if(tn == "pre")
      c = replace(c-"\r", "\n\n", "\n");
    return make_container( tn, m, html_encode_string(c) );
  }

  void create(string _tn)
  {
    tn = _tn;
  }
}

static string highlight_enriched( string from, object id )
{
  string a, b, c;
  while(sscanf(from, "%s<<%s>%s", a, b, c)==3)
    from = a+"&lt;"+b+"&gt;"+c;
  
  from = parse_html( describe_body(from,0,1), ([ ]), 
		     ([ 
		       "nofill":Tag("pre"),
		       "bold":Tag("b"),
		     ]));

  from = replace(from-"\r","\n>","<br>&gt;");
  return replace(from, "\n\n", "\n<br>\n");
}

static int gettime( int year, string month, int date, int hour, 
		    int minute, int second, string tz )
{
  int houradd;
  int minuteadd;
  sscanf(tz[1..2], "%d", houradd);
  sscanf(tz[3..4], "%d", minuteadd);
  if(tz[0]=='+')
  {
    houradd = -houradd;
    minuteadd = -minuteadd;
  }
  hour += houradd;
  minute += minuteadd;
  if(minute < 0)
  {
    hour--;
    minute += 60;
  }
  if( minute >= 60 )
  {
    hour++;
    minute -= 60;
  }
  if(hour < 0)
  {
    date--;
    hour+=24;
  }
  if(hour >= 24)
  {
    date++;
    hour-=24;
  }
  if(year > 1900) year -= 1900;

  mapping mt=([]);
  mt->year = year;
  mt->mon = MONTHS[month];
  mt->mday = date;
  mt->hour = hour;
  mt->min = minute;
  mt->sec = second;
  // We do not care about date being out of range. mktime() can handle 
  // that automatically.
  
  mapping lt = localtime(time());
  return mktime( mt )-lt->timezone+(lt->isdst?3600:0);
}

static string describe_time_period( int amnt )
{
  amnt/=60;
  if(amnt < 120) return amnt+" minutes";
  amnt/=60;
  if(amnt < 48) return amnt+" hours";
  amnt/=24;
  if(amnt < 60) return amnt+" days";
  amnt/=(365/12);
  if(amnt < 30) return amnt+" months";
  amnt/=12;
  return amnt+" years";
}

static mapping extended_headers( mapping from )
{
  from = copy_value( from );
  if(from->date)
  {
    int when;
    int date, year, hour, minute, second;
    string month, tz;

    // Fri, 11 Sep 1998 22:59:18 +0200 (MET DST)
    // Sun, 13 Sep 1998 22:05:06 +0200
//     werror("date is: '%s' (%{0x%x %})\n", from->date, values(from->date));
    if(sscanf(from->date, 
	      "%*s, %d %s %d %d:%d:%d %s", 
	      date, month, year, hour, minute, second, tz ) == 8)
    {
//       werror("match in 1\n");
      when = gettime( year, month, date, hour, minute, second, tz );
    }

    // 10 Sep 1998 21:51:35 -0700
    if(sscanf(from->date, 
	      "%d %s %d %d:%d:%d %s", 
	      date, month, year, hour, minute, second, tz ) == 7)
      when = gettime( year, month, date, hour, minute, second, tz );

    if(when) 
    {
      int delay = time() - when;
      from->reldate = describe_time_period( delay )+" ago";
    }
  }
  if(!from->reldate)
    from->reldate="Unknown (unparsable date)";
  return from;
}

static string fix_urls(string s)
{
  string *foo;
  if(foo=regexp::split(s))
    return fix_urls(foo[0])+
      "<a target=Remote href=\""+foo[1]+"\">"+foo[1]+"</a>"+
      fix_urls(s[strlen(foo[0])+strlen(foo[1])..0x7fffffff]);
  return s;
}


inline string qte(string what)
{
  return fix_urls(replace(what, ({ "<", ">", "&", }),
			  ({ "&lt;", "&gt;", "&amp;" })));
}

static string quote_color_for( int level )
{
  switch(level)
  {
   case 1: return "#dd0000";
   case 2: return "darkred";
   case 3: return "darkblue";
   case 4: return "#005500";
   default: return "#0077ee";
  }
}

static string describe_body(string bdy, mapping m, int|void nofuss)
{
  int br;
  string res="";
  if(!nofuss)
  {
    if(!m->freeform) 
      res = "<pre>";
    else  
      br = 1;
  }

  string ql;
  int lq, cl;
  foreach(bdy/"\n", string line)
  {
    int quote = 0;
    string q = replace(line, ({" ","|"}), ({"",">"}));
    if(!lq && sscanf(q, "%[>]", ql))
      quote = strlen(ql);

    if(!strlen(line))
    {
      if(br) res += "<br>";
      res += "\n";
      continue;
    }
    if(quote!=cl)
    {
      if(cl)
	res += "</font>";
      if(quote)
	res += "<font color="+quote_color_for(quote)+" size=-1>";
      cl=quote;
    }
    if(!lq && (q=="--" || q=="---"))
    {
      res+=(br?"<pre>":"") + "<font color=darkred>";
      br=0;
      lq=1;
    }
    res += (nofuss ? line : qte(line))+"\n" ;
    if(br) res +="<br>";
  }
  if(lq || cl)
    res += "</font>";
  if(!br) res += "</pre>";
  return res;
}

static string highlight_mail(string from, object id)
{
  return describe_body( from, id->variables );
}

static mapping common_callers( string prefix )
{
  mapping tags = ([]);
  foreach(glob(prefix+"*",indices(this_object())), string s)
  {
    if(!debug && search( s, "debug") != -1)
      continue;
    tags[replace(s[strlen(prefix)..], "_", "-")] = this_object()[s];
  }

  DEBUG(( "Tags for %s is %s\n",prefix,
	  String.implode_nicely(sort(indices(tags)))));
  return tags;
}

static string verify_ownership( Mail mailid, object id )
{
  if(!secure) return 0;
  if(mailid->user != UID) 
  {
    id->realauth = 0;
    return login( id );
  }
}

static int num_unread(Mailbox from)
{
//   int res;
//   werror("%O\n", from->flags());
  return from->num_unread();
//   foreach(from, Mail m)
//     if(!m->flags()->read)
//       res++;
//   return res;
}

static mapping parse_headers( string foo )
{
  return mymesg->parse_headers( foo )[0];
}

static mapping make_flagmapping(multiset from)
{
  return mkmapping( Array.map(indices(from), lambda(string s) {
					       return "flag_"+s;
					     }),
		    ({"set"})*sizeof(from));
}

mapping _login = http_auth_required( "E-Mail" );
mapping (string:User) uid_cache = ([]);
string login(object id)
{
  string force = ("Permission denied");

  if(!clientlayer) 
    init_clientlayer( conf );

  if(!clientlayer)
    return "Internal server error";

  if(!id->realauth) 
  {
    id->misc->defines[" _extra_heads"] = _login->extra_heads;
    id->misc->defines[" _error"] = _login->error;
    return force;
  }

  if(!UID)
  {
    if(!(UID = uid_cache[ id->realauth ]))
    {
      UID = clientlayer->get_user(  @(id->realauth/":") );
      if(!UID) 
      {
	id->misc->defines[" _extra_heads"] = _login->extra_heads;
	id->misc->defines[" _error"] = _login->error;
	return force;
      }
      uid_cache[ id->realauth ] = UID;
    }
  }
}


/* Tag functions --------------------------------------------------- */

// <delete-mail mail=id>
// Please note that this function only removes a reference from the
// mail, if it is referenced by e.g. other clients, or is present in
// more than one mailbox, the mail will not be deleted.

string tag_delete_mail(string tag, mapping args, object id)
{
  string res;
  Mail mid = clientlayer->get_cache_obj( clientlayer->Mail, args->mail );
  if(res = login(id))
    return res;
  if(mid && mid->user == UID )
    mid->mailbox->remove_mail( mid );
  return "";
}

// <mail-body mail=id>
string tag_mail_body(string tag, mapping args, object id)
{
  string res;
  if(res = login(id))
    return res;

  Mail mail = clientlayer->get_cache_obj( clientlayer->Mail, args->mail );
  if(res = login(id))
    return res;
  if(mail && mail->user == UID )
    return mail->body( );
}

// <mail-verify-login>
//  .. page ...
// </mail-verify-login>

string container_mail_verify_login(string tag, mapping args, 
				   string contents, object id)
{
  string q = login(id);
  if(q) return q;
  return contents;
}

// <list-mailboxes>
//  #name# #id# #unread# #read# #mail#
// </list-mailboxes>
string container_list_mailboxes(string tag, mapping args, string contents, 
				object id)
{
  string res;
  if(res = login(id))
    return res;

  UID->get_incoming();
//   UID->get_drafts();

  array(mapping) vars = ({});
  foreach(UID->mailboxes(), Mailbox m)
    vars += ({ ([
      "_mb":m,
      "name":m->name,
      "id":m->id,
    ]) });

  if(!args->quick)
  {
    foreach(vars, mapping v)
    {
      v->mail = (string)sizeof(v->_mb->mail());
      v->unread = (string)num_unread( v->_mb );
      v->read = (string)((int)v->mail - (int)v->unread);
      m_delete(v, "_mb");
    }
  }
  return do_output_tag( args, vars, contents, id );
}

string tag_mail_next( string tag, mapping args, object id )
{
  Mailbox mbox;
  array(Mail) mail;
  int i;
  int start;

  if(string res = login(id))
    return res;

  foreach( UID->mailboxes(), Mailbox m )
    if(m->id == (int)id->variables->mailbox_id )
    {
      mbox = m;
      break;
    }
  if(!mbox) return "No mailbox!\n";

  //   mail = Array.filter(mbox->mail(), filter_mail_list, id);
  // This _must_ be faster. This does not scale well enough!
  // So. Let's apply the filter one mail at a time instead.
  // That should be slightly faster..
  mail = mbox->mail();

  if( ((int)id->variables->index < sizeof(mail))
      && mail[ (int)id->variables->index ]->id == id->variables->mail_id)
    start = (int)id->variables->index;
  else
    if(id->variables->mail_id)
      start = search(mail->id, id->variables->mail_id);

//   werror("index is now: %d (%s) %O\n", start, 
// 	 (string)id->variables->index,
// 	 id->variables);

  if(args->previous)
  {
    for(i = start-1; i>=0; i--)
      if(filter_mail_list( mail[i],id ) )
      {
	start = i;
	break;
      }
  } 
  else
  {
    for(i = start+1; i<sizeof(mail); i++)
      if(filter_mail_list( mail[i],id ) )
      {
	start = i;
	break;
      }
    if(start != i)
      for(i = 0; i<start; i++)
	if(filter_mail_list( mail[i],id ) )
	{
	  start = i;
	  break;
	}
  }

//   werror("index after: %d\n", start);
  if(start >= sizeof(mail))
    start = sizeof(mail)-1;
//   werror("adjusted index: %d\n", start);
  if(start < 0)
    start = 0;

  id->variables->index = (string)start;
  if(sizeof(mail))
    return mail[ start ]->id;
  return "NOPE";
}

string tag_mail_make_hidden( string tag, mapping args, object id )
{
  mapping q = copy_value(id->variables);
  string res = "";

  q->i = (string)time() + (string)gethrtime();
  m_delete(q, "qm");   m_delete(q, "col"); m_delete(q, "gtextid");
  m_delete(q, "mailbox_id"); m_delete(q, "mail_match");
  foreach( indices(q), string v )
  {
    mapping w = ([ "type":"hidden" ]);
    w->name = (string)v;
    w->value = (string)q[v];
    res += make_tag( "input", w )+"\n";
  }
  return res;
}

string tag_process_move_actions( string tag, mapping args, object id )
{
  if(string res = login(id)) 
    return res;

  foreach( glob("move_mail_to_*.x", indices(id->variables)), string v)
  {
    string mbox;
    m_delete(id->variables, v);
    m_delete(id->variables, replace(v, ".x", ".y"));

    sscanf(v, "move_mail_to_%s.x", mbox);

    if(mbox)
    {
      Mailbox m = UID->get_or_create_mailbox( mbox );
      if(id->variables->mail_id)
      {
	id->variables["next.x"]="1";
	Mail mid = 
	  clientlayer->get_cache_obj(clientlayer->Mail,
				     id->variables->mail_id);
	if(!mid)
	  return "Unknown mail to move!\n";
	m->add_mail( mid );
	mid->mailbox->remove_mail( mid );
      }
    } else
      return "Unknown mailbox to move to!\n";
  }
}

string tag_process_user_buttons( string tag, mapping args, object id )
{
  if(string res = login(id)) 
    return res;

  array b = UID->get( "html_buttons" );

  if(!b) return "";

  foreach( glob("user_button_*.x", indices(id->variables)), string v)
  {
    int i;
    sscanf( v, "user_button_%d.x", i );
    m_delete(id->variables, v);
    m_delete(id->variables, replace(v, ".x", ".y"));

    if(i > -1 && i < sizeof(b))
      foreach(indices( b[ i ][ 2 ] ), string q)
	id->variables[ q+".x" ] = "1";
  }
  return "";
}

// <user-buttons type=type>
string tag_user_buttons( string tag, mapping args, object id )
{
  if(string res = login(id)) 
    return res;

  // A button is:
  //    ({ /* one button... */
  //      "title",
  //      (< when >),    /* From: "mail", "mailbox", "global" */
  //      (< "action", "action", .. >) /* List of atom actions. */
  //    }),
  //  
  //   There are also separators:
  //
  //   ({ "<br>",(< "when" >)}),
  //   ({ " ", (< "when" >) }),
  //
  // The configuration interface for this will be rather complex...
  // I do like this idea, though.
  //
  // Example: ({ "->archive, next",
  //             (< "mail" >),
  //             (< "move_mail_to_archived", "next_unread" >),
  //          })
  //  
  //  The move_mail_to_XXX action is rather special, you can have
  //  anything for XXX, it's used as the mailbox to move the mail to.
  // 
  //  This function only creates the buttons, it does not do the
  //  actions. Most of the actions, actually, all actions except
  //  move_mail_to_XXX, which is handled slightly differently, are
  //  handled from RXML.

  array b = UID->get( "html_buttons" );
  string res = "";
  if(!b)
    return "";
  werror("%O\n", b);
  for(int i = 0; i<sizeof(b); i++)
    if( b[i][ 1 ][ args->type ] )
    {
      if(sizeof(b[i])==2)
	res += b[i][0];
      else
      {
	mapping a = 
	([
	  "name":"user_button_"+i,
	  "value":b[i][0],
	]);
	res += make_tag( "gbutton", a );
      }
    }
  return res;
}

static int filter_mail_list( Mail m, object id )
{
  if(id->variables->mail_match)
    if(search(lower_case(values(m->headers())*"\n"),
	      lower_case(id->variables->mail_match))==-1)
      return 0;

  if(!m->flags()->deleted &&
     (id->variables->listall || 
      !m->flags()->read))
    return 1;

  return 0;
}


#define MAIL_PER_PAGE 20
// <list-mail-quick mailbox=id>
array(string) tag_list_mail_quick( string tag, mapping args, object id )
{
  string res;
  Mailbox mbox;

  if(res = login(id))
    return ({res});

  foreach( UID->mailboxes(), Mailbox m )
    if(m->id == (int)args->mailbox )
    {
      mbox = m;
      break;
    }

  if(!mbox)
    return ({"Invalid mailbox id"});

  string res="";
  
  mapping q= copy_value(id->variables);
  q->i = (string)time() + (string)gethrtime();
  m_delete(q, "qm");   m_delete(q, "col"); m_delete(q, "gtextid");
  string link="?mail_id=#id#&";
  
  foreach(sort(indices(q)), string v)
    if(q[v] != "0")
      link += v+"="+http_encode_url( q[v] )+"&";
  q = ([ "href":fix_relative(link[ .. strlen(link)-2 ], id) ]);

  link = "<td><font size=-1><HIGHLIGHT>"+make_tag("a", q);

  string bg;
  int q;
  array(Mail) mail = mbox->mail();
  string pre="";
  string post="";

  mail = Array.filter(mail, filter_mail_list, id);
  if(sizeof(mail) > MAIL_PER_PAGE)
  {
    int start = (int)id->variables->mail_list_start;
    if(start > sizeof(mail)-MAIL_PER_PAGE)
      start = sizeof(mail)-MAIL_PER_PAGE;
    if(start < 0)
      start = 0;
    mapping m = ([]);
    if(start > 0)
    {
      m->mail_list_start = (string) (start - MAIL_PER_PAGE);
      pre = ("<tr><td bgcolor=#ddeeff colspan=2>"+
	     container_mail_a( "gtext", m,"Older messages",id)+
	     "</td></tr>");
    }
    if(start < sizeof(mail)-MAIL_PER_PAGE)
    {
      m->mail_list_start = (string) (start + MAIL_PER_PAGE);
      post = ("<tr><td bgcolor=#ddeeff colspan=2>"+
	      container_mail_a( "gtext", m,"Newer messages",id)+
	      "	</td></tr>");
    }
    mail = mail[ start .. start+MAIL_PER_PAGE-1 ];
  }

  foreach(mail, Mail m)
  {
    string f = replace(link,({"HIGHLIGHT","#id#"}),({
      m->flags()->read?"i":"b",m->id}));
    mapping h = m->decoded_headers();
    if(h->subject && h->from)
    {
      if(q++%2)
	bg = " bgcolor=#ffeedd";
      else
	bg = "";
      res += `+("<tr"+bg+">",
		f,
		html_encode_string(h->subject),
		"</td>",
		f,
		html_encode_string(h->from),
		"</td></tr>\n");
    }
  }
  return ({ pre+res+post });
}

string tag_process_mail_actions( string tag, mapping args, object id )
{
  foreach(glob("list_*.x", indices(id->variables)), string v)
  {
    switch(v-".x")
    {
     case "list_unread":
       m_delete(id->variables, "mail_id");
       m_delete(id->variables, "listall");
       break;
     case "list_all":
       m_delete(id->variables, "mail_id");
       id->variables->listall = "1";
       break;
     case "list_match":
       m_delete(id->variables, "mail_id");
       break;
     case "list_clear":
       m_delete(id->variables, "mail_id");
       m_delete(id->variables, "mail_match");
       break;
    }
  }

  if(id->variables->mail_id)
  {
    if(id->variables["delete.x"])
      tag_delete_mail( "delete", ([ "mail":id->variables->mail_id ]), id );

    if(id->variables["next.x"])
      id->variables->mail_id = tag_mail_next(tag,([]),id);
    else if(id->variables["previous.x"])
      id->variables->mail_id = tag_mail_next(tag,(["previous":"1"]),id);
  }

  foreach(glob("*.x", indices(id->varibales)), string v)
  {
    m_delete(id->variables, v);
    m_delete(id->variables, replace(v, ".x", ".y"));
  }
}

// <list-mail mailbox=id>
//   #subject# #from# etc.
// </list-mail>
string container_list_mail( string tag, mapping args, string contents, 
			     object id )
{
  string res;
  Mailbox mbox;

  int start = (int)args->start;
  int num = (int)args->num;

  if(res = login(id))
    return res;

  foreach( UID->mailboxes(), Mailbox m )
    if(m->id == (int)args->mailbox )
    {
      mbox = m;
      break;
    }

  if(!mbox)
    return "Invalid mailbox id";
  
  if(!num) num = 1000;
  
  array variables = ({ });
  array m = mbox->mail();
  if(start < 0)
    start = sizeof(m)+start;
  foreach(m[start-1..start+num-2], Mail m)
    variables += ({ (["id":m->id]) |
		    m->decoded_headers()   | 
		    make_flagmapping( m->flags() ) });
  return do_output_tag( args, variables, contents, id );
}

string container_mail_a( string tag, mapping args, string c, object id )
{
  mapping q= copy_value(id->variables);
  q |= args;
  q->i = (string)time() + (string)gethrtime();
  m_delete(q, "fg");   m_delete(q, "bg");
  m_delete(q, "font"); m_delete(q, "link");
  string link="?";
  
  foreach(sort(indices(q)), string v)
    if(q[v] != "0")
      link += v+"="+http_encode_url( q[v] )+"&";
  q = ([ "href":fix_relative(link[ .. strlen(link)-2 ], id) ]);
  if(tag == "gtext")
  {
    q->magic = "magic";
    q->bg = "#ddeeff";
    q->fg = "black";
    q->scale = "0.5";
    return make_container("gtext", q, c );
  }
  return make_container("a", q, c );
}

string tag_amail_user_variable( string tag, mapping args, object id )
{
  mixed res;
  if(res = login(id))
    return res;
  if( args->set )
    return UID->set( "amhc_"+args->variable, args->set );
  else
    return (string)(UID->get( "amhc_"+args->variable ) || args["default"]);
}

// <mail-body-part mail=id part=num>
//
// Part 0 is the non-multipart part of the mail.
// If part > the available number of parts, part 0 is returned.
MIME.Message last_mail_mime;
string last_mail;

string tag_mail_body_part( string tag, mapping args, object id )
{
  MIME.Message m;
  if(args->mail == last_mail)
    m = last_mail_mime;
  else
    m = MIME.Message( tag_mail_body( tag, args, id ) );


  if(args->part == "xface")
  {
    id->misc->moreheads = ([ "Content-type":"image/gif",
			     "Content-disposition":"inline; "
			     "filename=\"xface.gif"]);
    return Image.GIF.encode( Image.XFace.decode( m->headers["x-face"] )->scale(0.8)->gamma(0.8) );
  } else {
    mixed res;
    object p;
    if(res = login(id))
      return res;
    foreach( (array(int))(args->part / "/" - ({""})), int p )
    {
      if(m->body_parts&& sizeof(m->body_parts) > p )
	m = m->body_parts[ p ];
    }
    p=m;
    id->misc->moreheads = ([ "Content-type":p->type+"/"+p->subtype,
			     "Content-disposition":"inline; "
			     "filename=\""+replace(args->name,"\"","\\\"")+
			     "\""]);
    return p->getdata();
  }
}

// <mail-body-parts mail=id
//             binary-part-url=URL
//	            (default not_query?mail=#mail#&part=#part#&name=#name#)
//             image-part-format='...#url#...'
//                  (default <a href='#url#'><img src='#url#'>
//                           <br>#name# (#type#)<br></a>)
//             binary-part-format='...#url#...'
//                  (default <a href='#url#'>Binary data #name# (#type#)</a>)
//             html-part-format='...#data#...'
//                  (default <table><tr><td>#data#</td></tr></table>)
//             text-part-format='...#data#...'>
//                  (default #data#)
//    full mime-data
// </mail-body-parts>

array(string) container_mail_body_parts( string tag, mapping args,
					 string contents, object id)
{
  return ({ low_container_mail_body_parts( tag, args, contents, id, 0 ) });
}

string low_container_mail_body_parts( string tag, mapping args, 
				      string|object contents, 
				      object id, string|void partpre)
{
  if(!stringp(partpre)) partpre="";
  if(id->prestate->raw) return "<pre>"+html_encode_string(contents)+"</pre>";

  MIME.Message msg;
  if(stringp(contents) && args->mail == last_mail)
  {
    msg = last_mail_mime;
  }
  else
  {
    array r;
    r = catch {
      msg = objectp(contents)?contents:MIME.Message( contents );
    };
//     werror(msg->type+"/"+msg->subtype+"\n");
//     if(msg && sizeof(msg->headers["content-type"]/"\n")>1)
//     {
//       // This is probably a "normal" sendmail bug message. *�(#�
//       // we have to verify this somewhat...
      
//     }
    if(!msg)
    {
      string delim, presumed_contenttype = " text/plain";
      if(sscanf(contents, "%*s--NeXT-Mail%s\n",delim) == 2)
	delim = "NeXT-Mail"+delim;

      sscanf(lower_case(contents), "%*s\ncontent-type:%s\n", 
	     presumed_contenttype);

      if(sscanf(contents, "%*s\r\n\r\n%s", contents)!=2)
	sscanf(contents, "%*s\n\n%s", contents);

      catch {
	if(delim)
	  msg = MIME.Message("Content-type: multipart/mixed; boundary="+delim+"\r\n\r\n"+contents);
	else 
	  msg = MIME.Message("Content-type:"+presumed_contenttype+
			     "\r\n\r\n"+contents);
      };
      if(!msg)
	return "Illegal mime message: "+r[0]+"\n <pre>"+
	  html_encode_string((string)contents)+"</pre>";
    }
    if(stringp(contents))
    {
      last_mail = args->mail;
      last_mail_mime = msg;
    }
  }

  string html_part_format = (args["html-part-format"] || 
			     "<table><tr><td>#data#</td></tr></table>");

  string text_part_format = (args["text-part-format"] || "#data#");

  string binary_part_format = (args["binary-part-format"] || 
			     "<a href='#url#'>#name# (#type#)"
			       "</a>");

  string image_part_format = (args["image-part-format"] || 
			     "<a href='#url#'><img border=0 src='#url#'>"
			      "<br>#name# (#type#)<br></a>");

  string binary_part_url = (fix_relative(args["binary-part-url"]
					 ||"display.html?mail=#mail#"
					 "&part=#part#&name=#name#",id));

  string res="";

  if(msg->body_parts)
  {
    int i;
    if(msg->subtype != "alternative" && msg->subtype != "related")
    {
      foreach(msg->body_parts, object msg)
      {
	if(msg->body_parts)
	{
	  res += low_container_mail_body_parts( tag, args, msg, id,
					    partpre+"/"+i );
	} 
	else if(msg->type == "message" && msg->subtype == "rfc822") 
	{
	  res += "<font size=-1>"+
	    replace(text_part_format, "#data#",
		    low_container_mail_body_parts(tag,args,
					  MIME.Message(msg->getdata()),
						  id,partpre+"/"+i))+
	    "</font>";
	}
	else if(msg->type == "text")
	{
	  if(msg->subtype == "html")
	    res += replace( html_part_format, "#data#", msg->getdata() );
	  else if(msg->subtype == "enriched")
	    res += replace( html_part_format, 
			    "#data#", 
			    highlight_enriched(msg->getdata(),id) );
	  else
	    res += replace( text_part_format, "#data#", 
			    highlight_mail(msg->getdata(),id));
	} 
	else 
	{
	  string format;
	  if(msg->type == "image") 
	    format = image_part_format;
	  else
	    format = binary_part_format;

	  mapping q = ([ "#url#":replace(binary_part_url,
					 ({"#mail#", "#part#","#name#" }),
					 ({ args->mail,partpre+"/"+(string)i, 
					    http_encode_string(msg->
							       get_filename()
						       ||"unknown name")
					 })),
			 "#name#":html_encode_string(msg->get_filename()
						     ||"unknown name"),
			 "#type#":html_encode_string(msg->type+"/"
						     +msg->subtype),
	  ]);
	  res += replace( format, indices(q), values(q) );
	}
	i++;
      }
    }
    else 
    {
      if(msg->subtype == "alternative")
      {
	object m = msg->body_parts[0];
	int p=1;
	foreach(msg->body_parts[1..], object msg)
	{
	  if( type_score( msg ) > type_score( m ) )
	  {
	    i = p;
	    m = msg;
	  }
	  p++;
	}
	res += low_container_mail_body_parts(tag,args,m,id,partpre+"/"+i);
      } 
      else 
      {
	if( msg->body_parts[0]->type != "text" ||
	    msg->body_parts[0]->subtype != "html" )
	  res += low_container_mail_body_parts( tag, args, 
					    msg->body_parts[0], 
					    id, partpre+"/0" );
	else 
	{	
	  string data =  msg->body_parts[0]->getdata();
	  data = parse_html(data, ([ "a":internal_odd_tag_href,
				     "img":internal_odd_tag_src,
				     "object":internal_odd_tag_src,
				     "embed":internal_odd_tag_src,
	  ]), ([]), replace(binary_part_url, ({"#mail#","#name#"}), 
			    ({args->mail, args->mail+".gif"})),partpre);

	  res += replace( html_part_format, "#data#", data );
	}
      }
    }
  } 
  else 
  {
    if(msg->type == "text")
    {
      if(msg->subtype == "html")
	res += replace( html_part_format, "#data#", msg->getdata() );
      else if(msg->subtype == "enriched")
	res += replace( html_part_format, 
			"#data#", 
			highlight_enriched(msg->getdata(),id) );
      else
	res += replace( text_part_format, "#data#", 
			highlight_mail(msg->getdata(),id));
    } 
    else 
    {
      string format;
      if(msg->type == "image") 
	format = image_part_format;
      else
	format = binary_part_format;
	
      mapping q = ([ "#url#":replace(binary_part_url,
				     ({"#mail#", "#part#", "#name#" }),
				     ({ args->mail, "/0", "#name#" })),
		     "#name#":html_encode_string(msg->get_filename())||"0.a",
		     "#type#":html_encode_string(msg->type+"/"+msg->subtype),
      ]);
      res += replace( format, indices(q), values(q) );
    }
  }
  return res;
}

// <debug-import-mail-from-dir dir=...>
//  Guess. :-)

string tag_debug_import_mail_from_dir( string tag, mapping args,
				       object id )
{
  if(!debug) return "Debug is not enabled!\n";

  if(mixed q = login( id )) 
    return q;
  Mailbox incoming = UID->get_incoming();

  string res = "Importing from "+args->dir+"<p>\n";
  foreach(sort(((array(int))get_dir( args->dir ))-({0})), int file)
    if(file_stat( args->dir+"/"+file )[ 1 ] > 0)
    {
      incoming->create_mail_from_fd( Stdio.File( args->dir+"/"+file, "r" ) );
      res+="<br>"+file+"\n";
    }
  return res;
}

// <mail-xface>xfacetext</mail-xface>
string container_mail_xface( string tag, mapping args, 
			     string contents, object id )
{
  if(strlen(contents))
  {
    args->src =
      fix_relative("display.html?part=xface&mail="+id->variables->mail_id+
		   "&name=xface.gif", id);
    return make_tag( "img", args );
  }
}

// <get-mail mail=id>
//   #subject# #from# #body# etc.
// </get-mail>
// NOTE: Body contains the headers. See <mail-body-parts>
string container_get_mail( string tag, mapping args, 
			   string contents, object id )
{
  string res;
  Mail mid = clientlayer->get_cache_obj( clientlayer->Mail, args->mail );

  if(!mid) return "Unknown mail!\n";
  
  if(res = login(id))
    return res;

  mid->set_flag( "read" );

  if(mid && mid->user == UID)
  {
    return do_output_tag( args,
			  ({ (mymesg->parse_headers(mid->body())[0])
			     |make_flagmapping(mid->flags())
			     |extended_headers(mid->decoded_headers())
			     |([ "body":mid->body() ])
			     |args }),
			  contents, id );
  }
  return "Permission denied.";
}
