/* This is a roxen module. (c) Informationsv�varna AB 1997.
 * $Id: killframe.pike,v 1.3 1997/05/24 13:51:36 grubba Exp $
 *
 * Adds some java script that will prevent others from putting
 * your page in a frame.
 * 
 * Will also strip any occurences of the string 'index.html' 
 * from the URL. Currently this is done a bit clumsy, making
 * URLs like http://www.roxen.com/index.html/foo.html break,
 * this should be fixed.
 * 
 * made by Peter Bortas <peter@infovav.se> Januari -97
 */

#include <module.h>
inherit "module";

void create() { }

mixed *register_module()
{
  return ({ 
    MODULE_PARSER,
    "Killframe tag",
      ("Makes pages frameproof."
       "<br>This module defines a tag,"
       "<pre>"
       "&lt;killframe&gt;: Adds some java script that will prevent others\n"
       "             from putting your page in a frame.\n\n"
       "             Will also strip any occurences of the string\n"
       "             'index.html' from the URL."
       "</pre>"
       ), ({}), 1,
    });
}

string tag_killframe( string tag, mapping m, object id )
{
  // Links to index.html are ugly.
  string my_url = id->conf->query("MyWorldLocation") + id->raw_url[1..] -
    "index.html";

  if (id->supports->javascript)
    string head = "<script language=javascript>\n"
      "<!--\n"
      "   if(top.location.href != \""+ my_url  +"\")\n"
      "     top.location.href = \""+ my_url  +"\";\n"
      "//-->"
      "</script>\n";
  
  return head;
}

mapping query_tag_callers()
{
  return ([ "killframe" : tag_killframe ]);
}
