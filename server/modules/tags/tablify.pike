/* This is a roxen module. Copyright � 1996 - 1999, Idonex AB.
 *
 * Converts tab and newline separated lists to tables.
 * 
 * made by Per Hedbor
 */

constant cvs_version = "$Id: tablify.pike,v 1.24 1999/07/23 04:43:16 nilsson Exp $";
constant thread_safe=1;
#include <module.h>
inherit "module";
inherit "wizard";

static private int loaded;

static private constant old_doc =
  ("Generates tables from, as an example, tab separated fields in newline"
   " separated records (this is the default)."
   "<p>This module defines a tag, {tablify}<p>Arguments:<br>"
   "help: This help<br>\n"
   "nice: Generate \"nice\" tables. The first row is the title row<br>\n"
   "nicer: Generate \"even nicer\" tables. The first row is the title row<br>\n"
   "cellseparator=str: Use str as the column-separator<br>\n"
   "rowseparator=str: Use str as the row-separator<br>\n"
   "cellalign=left|right|center: Align the contents of the cells<br>\n"
   "rowalign=left|right|center: Align the contents of the rows<br>\n");

static private string doc()
{
  return !loaded?"":replace(Stdio.read_bytes("modules/tags/doc/tablify")||
			    old_doc,
			    ({ "{", "}" }), ({ "&lt;", "&gt;" }));
}

mixed *register_module()
{
  return ({ 
    MODULE_PARSER,
    "Tablify", 
    "This tag generates tables.<p>"
    "<tt>&lt;tablify help&gt;&lt;/tablify&gt;</tt> gives help.\n\n<p>"+doc(),
    ({}), 1, });
}

void start(int num, object configuration)
{
  loaded = 1;
}

string html_nicer_table(array(string) subtitles, array(array(string)) table,
			mapping|void opt)
{
  /* Options:
   *   bordercolor, titlebgcolor, titlecolor, oddbgcolor, evenbgcolor, modulo,
   *   font, scale, face, size
   * Containers:
   *   <fields>[num|text, ...]</fields>
   */

  string r = "";

  if(!opt) opt = ([]);
  int m = (int)(opt->modulo?opt->modulo:1);
  r += ("<table bgcolor=\""+(opt->bordercolor||"#27215b")+"\" border=\"0\" "
	"cellspacing=\"0\" cellpadding=\"1\">\n"
	"<tr><td>\n");
  r += "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  if (subtitles) {
    r += "<tr bgcolor=\""+(opt->titlebgcolor||"#27215b")+"\">\n";
    foreach(subtitles, mixed s)
      r+=
	"<td align=\"left\"><gtext nfont=\""+(opt->font||"lucida")+"\" scale=\""+
	(opt->scale||"0.36")+"\" fg=\""+(opt->titlecolor||"white")+"\" bg=\""+
	(opt->titlebgcolor||"#27215b")+"\">"+s+"</gtext></td>";
    r += "</tr>";
  }
  
  int cols; // FIXME: Used in colspan below. Is never set!
  for(int i = 0; i < sizeof(table); i++) {
    string tr;
    r += tr = "<tr bgcolor=\""+((i/m)%2?opt->evenbgcolor||"#ddeeff":
			      opt->oddbgcolor||"#ffffff")+"\">";
    for(int j = 0; j < sizeof(table[i]); j++) {
      mixed s = table[i][j];
      if(arrayp(s))
	r += "</tr>"+tr+"<td colspan=\""+cols+"\">"+s[0]+" &nbsp;</td>";
      else {
	string type = "text";
	if(arrayp(opt->fields) && j < sizeof(opt->fields))
	  type = opt->fields[j];
	switch(type) {
	case "num":
	  array a = s/".";
	  r += "<td align=\"right\"><font color=\""+(opt->fgcolor||"#000000")+"\" size=\""+(opt->size||"2")+"\" face=\""+
	    (opt->face||"helvetica,arial")+"\">";
	  if(sizeof(a) > 1) {
	    r += (format_numeric(a[0])+"."+
		  reverse(format_numeric(reverse(a[1]), ";psbn&")));
	  } else
	    r += format_numeric(s, "&nbsp;");
	  break;
	case "text":
	default:
	  r += "<td><font color=\""+(opt->fgcolor||"#000000")+"\" size=\""+(opt->size||"2")+"\" face=\""+
	    (opt->face||"helvetica,arial")+"\">"+s;
	}
	r += "&nbsp;&nbsp;</font></td>";
      }
    }
    r += "</tr>\n";
  }
  r += "</table></td></tr>\n";
  r += "</table>"+(opt->noxml?"<br>":"<br />")+"\n";
  return r;
}


/* The meat of the module. Convert the contents of the tag (in 'q') to
 * a table. */

string container_fields(string name, mapping arg, string q,
			mapping m, mapping arg_list)
{
  arg_list->fields = q/(m->cellseparator||"\t");
  return "";
}

string tag_tablify( string tag, mapping m, string q, object request_id,
		    object file, mapping defines)
{
  array rows, res;
  string sep, td, color, table;
  int i;

#if 0
  sscanf(q, "%*[\n]%s", q);
  sscanf(reverse(q), "%*[\n]%s", q);
  q = reverse(q);
#endif

#if 1
  // RXML <1.4 compatibility stuff
  if(m->fgcolor0) {
    m->oddbgcolor=m->fgcolor0;
    m_delete(m, "fgcolor0");
  }
  if(m->fgcolor1) {
    m->evenbgcolor=m->fgcolor1;
    m_delete(m, "fgcolor1");
  }
  if(m->bgcolor) {
    m->bordercolor=m->bgcolor;
    m_delete(m, "bgcolor");
  }
#endif

  if(m->help) return register_module()[2];

  mapping arg_list = ([]);
  q = parse_html(q, ([]), (["fields":container_fields]), m, arg_list);

  if(sep = m->rowseparator)
    m->rowseparator = 0;
  else
    sep = "\n";

  rows = (q / sep) - ({""});
  
  if(sep = m->cellseparator)
    m->cellseparator = 0;
  else
    sep = "\t";

  if(m->cellalign)
  {
    td = "<td align=\""+m->cellalign+"\">";
    m->cellalign = 0;
  } else
    td="<td>";

  array title;
  if((m->nice||m->nicer) && (!m->notitle)) {
    title = rows[0]/sep;
    rows = rows[1..];
  }

  if(m->min)
    rows = rows[((int)m->min)..];
  if(m->max)
    rows = rows[..((int)m->max-1)];
  
  if(m->nice)
  {
    rows = Array.map(rows,lambda(string r, string s){return r/s;}, sep);
    return html_table(title, rows, m + arg_list);
  }

  if(m->nicer)
  {
    rows = Array.map(rows,lambda(string r, string s){return r/s;}, sep);
    return html_nicer_table(title, rows, m + arg_list);
  }
  
  for(i=0; i<sizeof(rows); i++)
    rows[i] = td + (rows[i]/sep) * ("</td>"+td) + "</td>";

  table = "<table";
  foreach(indices(m), td)
    if(m[td]) table += " "+td+"=\""+m[td]+"\"";

  table += ">";
  if(m->rowalign)
  {
    td = "<tr align=\""+m->rowalign+"\">";
    m->rowalign=0;
  } else
    td="<tr>";

  return table + td + rows*("</tr>\n"+td) + "</tr>\n</table>";
}

mapping query_container_callers()
{
  return ([ "tablify" : tag_tablify ]);
}

mapping query_tag_callers()
{
  return ([]);
}

