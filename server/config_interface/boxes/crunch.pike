/*
 * Locale stuff.
 * <locale-token project="roxen_config"> _ </locale-token>
 */
#include <roxen.h>
#define _(X,Y)	_DEF_LOCALE("roxen_config",X,Y)

constant box      = "large";
constant box_initial = 0;

String box_name = _(232,"Crunch activity");
String box_doc  = _(262,"Recently changed Crunch reports");

class Fetcher
{
  Protocols.HTTP.Query query;
  string crunch_date( int t )
  {
    mapping l = localtime(t);
    return (1900+l->year)+""+sprintf("%02d%02d",(l->mon+1),(l->mday));
  }

  void done( Protocols.HTTP.Query q )
  {
    crunch_data = Data( query->data() );
    cache_set( "box_data", "crunch", query->data(), 9000 );
    destruct();
  }
  
  void fail( Protocols.HTTP.Query q )
  {
    crunch_data = Data("");
  }

  void create()
  {
    call_out( Fetcher, 3600 );
    string url = "/crunch/changed.xml?date="+crunch_date( time()-24*60*60*7 );
    query = Protocols.HTTP.Query( )->set_callbacks( done, fail );
    query->async_request( "community.roxen.com", 80,
			  "GET "+url+" HTTP/1.0",
			  ([ "Host":"community.roxen.com:80" ]) );
  }
}


class Data( string data )
{
  class Bug( int id, string short, string created,
	     string product, string component,
	     string version, string opsys, string arch,
	     string severity, string priority, string status,
	     string resolution )
  {
    string format( )
    {
      if( product == "Roxen WebServer" &&
	  (version != roxen.__roxen_version__) )
	return "";

      if( (product == "Pike") && (abs((float)version - __VERSION__) > 0.09) )
	return "";
      
      if( status == "RESOLVED" )
	status = "<i>fixed</i>";
      resolution = "";
      return "<tr valign=top><td align=right><font size=-1>"
	"<a href='http://community.roxen.com/"+	id+"'>"+id+"</a></font></td>"
	"<td><font size=-1>"+(product - "Roxen ")+
	" <nobr>"+component+"</nobr></font></td>"
	"<td><font size=-1>"+short+"</font></td>"
	"<td><font size=-1>"+lower_case(status)+"</font></td></tr>";
    }
  }

  array(Bug) parsed;

  void parse_bug( Parser.HTML b, mapping m )
  {
    parsed += ({ Bug( (int)m->id, m->short, m->created,
		      m->product, m->component, m->version,
		      m->opsys, m->arch, m->severity,
		      m->priority, m->status, m->resolution ) });
  }
  
  void parse( )
  {
    parsed = ({});
    Parser.HTML()->add_tag( "bug", parse_bug )->finish( data )->read();
  }
  
  string get_page()
  {
    if(!parsed)
      parse();
    return "<table cellspacing=0 cellpadding=2>"+
      (parsed->format()*"\n")+"</table>";
  }
}

Data crunch_data;
Fetcher fetcher;
string parse( RequestID id )
{
  string contents;
  if( !crunch_data )
  {
    string data;
    if( !(data = cache_lookup( "crunch_data", "data" )) )
    {
      if( !fetcher )
	fetcher = Fetcher();
      contents = "Fetching data from Crunch...";
    } else {
      crunch_data = Data( data );
      call_out( Fetcher, 3600 );
      contents = crunch_data->get_page();
    }
  } else
    contents = crunch_data->get_page();

  return
    "<box type='"+box+"' title='"+box_name+"'>"+contents+"</box>";
}
