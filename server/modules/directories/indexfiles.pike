// This is a roxen module. Copyright � 1996 - 2000, Roxen IS.

// Index files only module, a directory module that will not try to
// generate any directory listings, instead only using index files.

constant cvs_version = "$Id: indexfiles.pike,v 1.19 2001/01/29 05:41:26 per Exp $";
constant thread_safe = 1;

inherit "module";
#include <module.h>

//<locale-token project="mod_indexfiles">LOCALE</locale-token>
#define LOCALE(X,Y)	_DEF_LOCALE("mod_indexfiles",X,Y)
// end locale stuff

//************** Generic module stuff ***************

constant module_type = MODULE_DIRECTORIES;
LocaleString module_name = LOCALE(1,"Index files only");
LocaleString module_doc  =
  LOCALE(2,"Index files only module, a directory module that will not try "
	 "to generate any directory listings, instead only using the  "
	 "specified index files."
	 "<p>You can use this directory module if you do not want "
	 "any automatic directory listings at all, but still want \n"
	 "to use index.html with friends</p>");

void create()
{
  defvar("indexfiles", ({ "index.xml", "index.html" }),
	 LOCALE(3,"Index files"), TYPE_STRING_LIST|VAR_NOT_CFIF,
	 LOCALE(4,"If one of these files is present in a directory, it will "
		"be returned instead of 'no such file'."));
}

// The only important function in this file...
// Given a request ID, try to find a matching index file.
// If one is found, return it, if not, simply return "no such file" (0)
mapping parse_directory(RequestID id)
{
  // Redirect to an url with a '/' at the end, to make relative links
  // work as expected.
  string f = id->not_query;
  if(strlen(f) > 1)
  {
    if(f[-1]!='/') return Roxen.http_redirect(f+"/", id);
    if(f[-1]=='/' && has_value(f, "//"))
      return Roxen.http_redirect("/"+(f/"/"-({""}))*"/"+"/", id);
  }

  foreach(query("indexfiles"), string file)
  {
    mapping result;
    id->not_query = f+file;
    if(result=id->conf->get_file(id))
      return result; // File found, return it.
  }
  id->not_query = f;
  return 0;
}
