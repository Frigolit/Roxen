// This is a roxen module. Copyright � 1996 - 2000, Roxen IS.

// The redirect module. Redirects requests from one filename to
// another. This can be done using "internal" redirects (much like a
// symbolic link in unix), or with normal HTTP redirects.

constant cvs_version = "$Id: redirect.pike,v 1.25 2000/04/28 17:32:02 mast Exp $";
constant thread_safe = 1;

#include <module.h>
inherit "module";
inherit "roxenlib";

private int redirs = 0;

void create()
{
  defvar("fileredirect", "", "Redirect patterns", TYPE_TEXT_FIELD|VAR_INITIAL,
	 "Redirect one file to another. The syntax is 'regexp to_URL',"
	 "or 'prefix to_URL', or 'exact file_name to_URL. More patterns "
	 "can be read from a file by using '#include &lt;filename&gt;' on a line. "
	 "The path is relative to the Roxen server directory in the real "
	 "filesystem. Other lines beginning with '#' are treated as comments.\n"

	 "<p>Some examples:'"
	 "<pre>"
         "/from/.*      http://to.roxen.com/to/%f\n"
         ".*\\.cgi       http://cgi.foo.bar/cgi-bin/%p\n"
	 "/thb/.*       %u/thb_gone.html\n"
	 "/roxen/       http://www.roxen.com/\n"
	 "exact /       /main/index.html\n"
	 "</pre>"

	 "A %f in the 'to' field will be replaced with the filename of "
	 "the matched file, %p will be replaced with the full path, and %u"
	 "will be replaced with this server's URL (useful if you want to send "
	 "a redirect instead of doing an internal one). The last two "
	 "examples are special cases. <p>"

	 "If the first string on the line is 'exact', the filename following "
	 "must match _exactly_. This is equivalent to entering ^FILE$, but "
	 "faster. "

	 "<p>You can use '(' and ')' in the regular expression to "
	 "separate parts of the from-pattern when using regular expressions."
	 " The parts can then be insterted into the 'to' string with "
	 " $1, $2 etc.\n" " <p>More examples:<pre>"
	 ".*/SE/liu/lysator/(.*)\.class    /java/classes/SE/liu/lysator/$1.class\n"
	 "/(.*).en.html                   /(en)/$1.html\n"
	 "(.*)/index.html                 %u/$1/\n</pre>"
	 ""
	 "If the to file isn't an URL, the redirect will always be handled "
	 "internally, so add %u to generate an actual redirect.<p>"
	 ""
	 "<b>Note 1:</b> "
	 "For speed reasons: If the from pattern does <i>not</i> contain "
	 "any '*' characters, it will not be treated like a regular "
	 "expression, instead it will be treated like a prefix that must "
	 "match exactly."

	 "<p><b>Note 2:</b> "
	 "Included files are not rechecked for changes automatically. You "
	 "have to reload the module to do that." );
}

array(string) redirect_from = ({});
array(string) redirect_to = ({});
mapping(string:string) exact_patterns = ([]);

void parse_redirect_string(string what)
{
  foreach(replace(what, "\t", " ")/"\n", string s)
  {
    if (sscanf (s, "#include %*[ ]<%s>", string file) == 2) {
      if(string contents=Stdio.read_bytes(file))
	parse_redirect_string(contents);
      else
	report_warning ("Cannot read redirect patterns from "+file+".\n");
    }
    else if (s[..0] != "#") {
      array(string) a = s/" " - ({""});
      if(sizeof(a)>=3 && a[0]=="exact") {
	if (exact_patterns[a[1]])
	  report_warning ("Duplicate redirect pattern %O.\n", a[1]);
	exact_patterns[a[1]] = a[2];
      }
      else if (sizeof(a)==2) {
	if (search (redirect_from, a[0]) >= 0)
	  report_warning ("Duplicate redirect pattern %O.\n", a[0]);
	redirect_from += ({a[0]});
	redirect_to += ({a[1]});
      }
      else if (sizeof (a))
	report_warning ("Invalid redirect pattern %O.\n", a[0]);
    }
  }
}

void start()
{
  redirect_from = ({});
  redirect_to = ({});
  exact_patterns = ([]);
  parse_redirect_string(QUERY(fileredirect));
}

constant module_type = MODULE_FIRST;
constant module_name = "Redirect Module v2.0";
constant module_doc  = "The redirect module. Redirects requests from one filename to "
  "another. This can be done using \"internal\" redirects (much"
  " like a symbolic link in unix), or with normal HTTP redirects.";
constant module_unique = 0;

string status()
{
  return sprintf("Number of patterns: %d+%d=%d, Redirects so far: %d",
		 sizeof(redirect_from),sizeof(exact_patterns),
		 sizeof(redirect_from)+sizeof(exact_patterns),
		 redirs);
}


mixed first_try(object id)
{
  string f, to;
  mixed tmp;

  if(id->misc->is_redirected)
    return 0;

  string m;
  int ok;
  m = id->not_query;
  if(id->query)
    if(sscanf(id->raw, "%*s?%[^\n\r ]", tmp))
      m += "?"+tmp;

  foreach(indices(exact_patterns), f)
  {
    if(m == f)
    {
      to = exact_patterns[f];
      ok=1;
      break;	
    }
  }
  if(!ok)
    for (int i = 0; i < sizeof (redirect_from); i++) {
      string f = redirect_from[i];
      if(!search(m, f))
      {
	to = redirect_to[i] + m[strlen(f)..];
	sscanf(to, "%s?", to);
	break;
      } else if(search(f, "*")!=-1) {
	array foo;
	function split;
	if(f[0] != '^') f = "^" + f;
	if(catch (split = Regexp(f)->split))
	  report_error("REDIRECT: Compile error in regular expression. ("+f+")\n");
	
	if((foo=split(m)))
	{
	  array bar = Array.map(foo, lambda(string s, mapping f) {
				       return "$"+(f->num++);
				     }, ([ "num":1 ]));
	  foo +=({(({""}) + (id->not_query/"/" - ({""})))[-1], id->not_query[1..] });
	  bar +=({ "%f", "%p" });
	  to = replace(redirect_to[i], (array(string)) bar, (array(string)) foo);
	  break;
	}
      }
    }

  if(!to)
    return 0;

  string url = id->conf->query("MyWorldLocation");
  url=url[..strlen(url)-2];
  to = replace(to, "%u", url);
  if(to == url + id->not_query || url == id->not_query)
    return 0;

  id->misc->is_redirected = 1; // Prevent recursive internal redirects

  redirs++;
  if((strlen(to) > 6 &&
      (to[3]==':' || to[4]==':' ||
       to[5]==':' || to[6]==':')))
  {
    to=replace(to, ({ "\000", " " }), ({"%00", "%20" }));

    return http_low_answer( 302, "")
      + ([ "extra_heads":([ "Location":to ]) ]);
  } else {
    id->variables = ([]);
    id->raw_url = http_encode_string(to);
    id->not_query = id->scan_for_query( to );
  }
}


