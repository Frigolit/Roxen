/*
 * Locale stuff.
 * <locale-token project="roxen_config"> _ </locale-token>
 */
#include <roxen.h>
#define _(X,Y)	_DEF_LOCALE("roxen_config",X,Y)

constant box      = "small";
String box_name = _(195,"Community articles");
String box_doc  = _(231,"Most recently published community articles");


string parse( RequestID id )
{
  string data;
  string contents;
  if( !(data = .Box.get_http_data( "community.roxen.com", 80,
			      "GET /boxes/articles.html HTTP/1.0" ) ) )
    contents = "Fetching data from community...";
  else
    contents = replace( data, ({ "/articles/",
				 "cellspacing=\"0\"",
				 "cellpadding=\"0\"",
				 "size=2",
			      }),
			({"http://community.roxen.com/articles/","","",""}));
  return ("<box type='"+box+"' title='"+box_name+"'>"+contents+"</box>");
}
