#include <roxen.h>
//<locale-token project="admin_tasks">LOCALE</locale-token>
#define LOCALE(X,Y)	_STR_LOCALE("admin_tasks",X,Y)

constant action = "status";
string name = LOCALE(0, "Active connection" );
string doc = LOCALE(0,"All currently active connection");

string parse( RequestID id )
{
  string res = "";
  foreach( roxen->configurations, Configuration c )
  {
    mapping q = c->connection_get();
    if( sizeof( q ) )
    {
      res += "<h2>"+c->query_name();
      array rows = ({});
      foreach( indices( q ), RequestID i )
      {
	if( i && q[i] )
	{
	  rows += ({
	    ([
	      "start":(q[i]->start || i->time),
	      "written":(int)q[i]->written,
	      "host":i->remoteaddr,
	      "closed":((!i->my_fd&&2) || !!catch(i->my_fd->query_address())),
	      "cc":q[i]->closed,
	      "file":i->not_query || "?",
	      "len":q[i]->len,
	      "stat":(i->file && i->file->stat) || (i->misc && i->misc->stat),
	      "hoststart":i->remoteaddr+sprintf("%010d",(time()-(q[i]->start || i->time))),
	      ])
	  });
	}
      }
      sort( column(rows,"hoststart"), rows );
      
      res += "<table cellspacing=0 border=0 cellpadding=2 width=100% >";
      res += "<tr bgcolor='&usr.fade2;'>"
	"<td><b>"+LOCALE(0,"File")+"</b></td>"
	"<td align=right><b>"+LOCALE(0,"Time")+"</b></td>"
	"<td align=right><b>"+LOCALE(0,"Sent (Mib)")+"</b></td>"
	"<td align=right><b>"+LOCALE(0,"Kibyte/s")+"</b></td>"
	"</tr>";
      float total_bw = 0.0, host_bw;
      string oh;
      foreach( rows, mapping r )
      {
	if( r->host != oh )
	{
	  if( oh )
	    res += sprintf("<tr bgcolor='&usr.fade2;'><td colspan=3>"
			   + roxen.quick_ip_to_host(oh)+
			   "</td><td align=right>%.1f</td>"
			   "</tr><tr><td>&nbsp;</td></tr>", host_bw);
	  oh = r->host;
	  host_bw = 0.0;
	}
	res += sprintf(
	  "<td>%s</td>"      // file
	  "<td align=right>%2dm %02ds</td>"     // time (min)
	  "<td align=right>%.1f / %s</td>" // sent
	  "<td align=right>%.1f</td>" // bw
          "</tr>",
	  r->file,
	  (time(1)-r->start)/60, (time(1)-r->start)%60,
          (r->written/1024.0/1024.0),
	  (r->len&&sprintf("%.1f", r->len/1024.0/1024.0 )) ||
	  (r->stat?sprintf("%.1f",r->stat[ST_SIZE]/1024.0/1024.0):" - "),
	  ((r->written)/(time(r->start)+0.1))/1024.0);

	if( !r->closed )
	{
	  host_bw +=  ((r->written)/(time(r->start)+0.1))/1024.0;
	  total_bw += ((r->written)/(time(r->start)+0.1))/1024.0;
	}
      }
      if( oh )
	res += sprintf("<tr bgcolor='&usr.fade2;'><td colspan=3>"
		       + roxen.quick_ip_to_host(oh)+
		       "</td><td align=right>%.1f</td></tr>"
		       "<tr><td>&nbsp;</td></tr>", host_bw);
      res +=
	sprintf("<tr bgcolor='&usr.fade2;'><td colspan=3>"
		+LOCALE(0,"Total bandwidth")+"</td>"
		"<td align=right>%.1f</td></tr>",
		total_bw );
      res += "</table>";
    }
  }
  res += "<input type=hidden name=action value='connections.pike' />"
    "<submit-gbutton>"+LOCALE(0,"Refresh")+"</submit-gbutton>";
  return res;
}
