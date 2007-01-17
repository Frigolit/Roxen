// Userfriendly-fetcher
// $Id: userfriendly.pike,v 1.2 2001/11/23 16:03:47 grubba Exp $

#include <roxen.h>

constant box="large";
constant box_initial = 0;

string box_name = "Userfriendly";
string box_doc  = "The Daily Static from Userfriendly";

string parse( RequestID id )
{
  string data;
  string contents="";

  if( !(data = .Box.get_http_data( "www.userfriendly.org",80, 
				   "GET /static/ HTTP/1.0" ) ))
    contents = "Fetching data from Userfriendly...";
  else
  {
    string img;
    sscanf( (map(data/"\n", lambda(string s){ 
			   if(search(s, "Latest Strip") != -1) 
			     return s; }) - ({ 0 }))[0], 
	    "%*sSRC=\"%s\"", img );
    if (img) {
      contents = 
	"<a href='http://www.userfriendly.org/static/'>"
	"<center><img src='"+img+"' /></center></a>";
    } else {
      // Probably offline.
      contents = data;
    }
  }
  return("<box type='"+box+"' title='"+box_name+"'>"+contents+"</box>");
  
}