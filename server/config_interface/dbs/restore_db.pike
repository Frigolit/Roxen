#include <config_interface.h>
#include <config.h>
#include <roxen.h>
//<locale-token project="roxen_config">_</locale-token>
#define _(X,Y)	_STR_LOCALE("roxen_config",X,Y)

mapping|string parse( RequestID id )
{
  string res = "";

  array(mapping) backups = DBManager.backups(0);
  mapping(string:array(mapping)) bks = ([]);
  foreach( backups, mapping m )
    if( !bks[m->db] )
      bks[m->db] = ({ m });
    else
      bks[m->db] += ({ m });
  
  if( !id->variables->db )
  {
    foreach( sort( indices( bks ) ), string bk )
    {
      mapping done = ([ ]);
      res += "<gtext scale='0.6'>"+bk+"</gtext>";
      res += "<table>";
      res += "<tr><td></td><td><b>"+_(0,"Directory")+"</b></td><td><b>"+
	_(0,"Date")+"</b></td></tr>\n";

      foreach( bks[bk], mapping b )
      {
	if( !done[b->directory] )
	{
	  done[b->directory] = ({
	    b->whn, b->directory,
	    ({ b->tbl }),
	    "<a href='restore_db.pike?db="+Roxen.html_encode_string(bk)
	    +"&dir="+Roxen.html_encode_string( b->directory )+"'>"+
	    "<gbutton>"+_(0,"Restore")+"</gbutton></a>"
	    "<a href='restore_db.pike?db="+Roxen.html_encode_string(bk)
	    +"&dir="+Roxen.html_encode_string( b->directory )+"&drop=1'>"+
	    "<gbutton>"+_(0,"Delete")+"</gbutton></a>"
	  });
	}
	else
	  done[b->directory][2] += ({ b->tbl });
      }

      foreach( sort( values( done ) ), array r )
      {
	res += "<tr>";
	res += "  <td>"+r[3]+"</td>\n";
	res += "  <td>"+r[1]+"</td>\n";
	res += "  <td>"+isodate((int)r[0])+"</td>\n";
	res += "</tr>";
      }
      res += "</table>";
    }
  }
  else
  {
    if( id->variables->drop )
    {
      DBManager.delete_backup( id->variables->db, id->variables->dir );
      return Roxen.http_redirect("/dbs/backups.html", id );
    }
    else if( id->variables["ok.x"] )
    {
      array tables = ({});
      foreach( glob( "bk_tb_*", indices( id->variables )), string tb )
	tables += ({ tb[6..] });
      DBManager.restore( id->variables->db,
			 id->variables->dir,
			 id->variables->todb,
			 tables );
      return Roxen.http_redirect("/dbs/backups.html", id );
    }
    else
    {
      array possible = ({});
      foreach( bks[ id->variables->db ], mapping bk )
	if( bk->directory == id->variables->dir )
	  possible += ({ bk->tbl });

      res += "<gtext scale=0.5>"+
	_(0,"Restore the following tables from the backup")+
	"</gtext> <br />"
	"<input type=hidden name=db value='&form.db:http;' />"
	"<input type=hidden name=dir value='&form.dir:http;' />";
      
      res += "<blockquote><table>";
      int n;
      foreach( possible, string d )
      {
	if( n & 3 )
	  res += "</td><td>";
	else if( n )
	  res += "</td></tr><tr><td>\n";
	else
	  res += "<tr><td>";
	n++;
	res += "<input name='bk_tb_"+Roxen.html_encode_string(d)+
	  "' type=checkbox checked=checked />"+
	  d+"<br />";
      }
      res += "</td></tr></table>";

      res +=
	"</blockquote><gtext scale='0.5'>"+
	_(0,"Restore the tables to the following database")
	+"</gtext><blockquote>";

      res += "<select name='todb'>";
      foreach( sort(DBManager.list()), string db )
      {
	if( db == id->variables->db )
	  res += "<option selected=selected>"+db+"</option>";
	else
	  res += "<option>"+db+"</option>";
      }
      res += "</select>";
      
      res += "</blockquote><table width='100%'><tr><td>"
	"<submit-gbutton2 name='ok'>"+_(0,"Ok")+"</submit-gbutton2></td>\n"
	"<td align=right><a href=''><gbutton> "+
	_(0,"Cancel")+" </gbutton></a></td>\n</table>\n";
    }
  }
  if( !id->variables->db )
    return Roxen.http_string_answer(res);
  return
    "<use file='/template'/><tmpl>"
    "<topmenu base='../' selected='dbs'/>"
    "<content><cv-split><subtablist width='100%'><st-tabs>"
    "<insert file='subtabs.pike'/></st-tabs><st-page>"
    "<input type=hidden name='sort' value='&form.sort:http;' />\n"
    "<input type=hidden name='db' value='&form.db:http;' />\n"
    +
    res
    +"</st-page></subtablist></cv-split></content></tmpl>";
}
