// This is a roxen module. Copyright � 2000 - 2001, Roxen IS.

inherit "module";

constant cvs_version = "$Id: whitespace_sucker.pike,v 1.6 2001/09/03 18:12:20 nilsson Exp $";
constant thread_safe = 1;
constant module_type = MODULE_FILTER;
constant module_name = "Whitespace Sucker";
constant module_doc  = "Sucks the useless guts away from of your pages.";

void create() {

  defvar("comment", Variable.Flag(0, 0, "Strip HTML comments",
				  "Removes all &lt;!-- --&gt; type of comments") );
  defvar("verbatim", Variable.StringList( ({ "pre", "textarea", "script", "style" }),
					  0, "Verbatim tags",
					  "Whitespace stripping is not performed on the contents "
					  "of these tags." ) );
}

int gain;

string status()
{
  return sprintf("<b>%d bytes</b> of useless whitespace have been dropped.", gain);
}

static string most_significant_whitespace(string ws)
{
  int size = sizeof( ws );
  if( size )
    gain += size-1;
  return !size ? "" : has_value(ws, "\n") ? "\n"
		    : has_value(ws, "\t") ? "\t" : " ";
}

static array(string) remove_consecutive_whitespace(Parser.HTML p, string in)
{
  sscanf(in, "%{%[ \t\r\n]%[^ \t\r\n]%}", array ws_nws);
  if(sizeof(ws_nws))
  {
    ws_nws = Array.transpose( ws_nws );
    ws_nws[0] = map(ws_nws[0], most_significant_whitespace);
  }
  return ({ Array.transpose( ws_nws ) * ({}) * "" });
}

array(string) verbatim(Parser.HTML p, mapping(string:string) args, string c) {
  return ({ p->current() });
}

mapping filter(mapping result, RequestID id)
{
  if(!result
  || search(result->type, "text/")
  || !stringp(result->data)
  || id->prestate->keepws
  || id->misc->ws_filtered++)
    return 0;

  Parser.HTML parser = Parser.HTML();
  foreach(query("verbatim"), string tag)
    parser->add_container( tag, verbatim );
  parser->add_quote_tag("!--", query("comment")&&"", "--");
  parser->_set_data_callback( remove_consecutive_whitespace );
  result->data = parser->finish( result->data )->read();
  return result;
}
