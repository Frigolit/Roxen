#include <config.h>
constant cvs_version = "$Id: builtin.pike,v 1.2 2000/09/19 10:30:45 nilsson Exp $";

constant name = "Builtin fonts";
constant doc =  "Fonts included in pike (and roxen)";

inherit FontHandler;

array available_fonts()
{
  return ({ "pike builtin", "roxen builtin" });
}

array(mapping) font_information( string fnt )
{
  switch( replace(lower_case(fnt)," ","_")-"_" )
  {
   case "pikebuiltin":
     return ({
              ([
                "name":"pike builtin",
                "family":"Pike builtin font",
                "path":"-",
                "style":"normal",
                "format":"bitmap dump",
              ])
            });
   case "roxenbuiltin":
     return ({
              ([
                "name":"roxen builtin",
                "family":"Roxen builtin font",
                "path":"-",
                "style":"normal",
                "format":"scalable vector font",
              ])
            });
  }
}

array has_font( string name, int size )
{
  switch( replace(lower_case(name)," ","_")-"_" )
  {
   case "pikebuiltin":
   case "roxenbuiltin":
     return ({ "nn" });
  }
  return 0;
}

Font open( string name, int size, int bold, int italic )
{
  switch( replace(lower_case(name)," ","_")-"_" )
  {
   case "pikebuiltin":
     return Image.Font();
   case "roxenbuiltin":
     return Image.Font(); // for now. Will use the cyberbit sans font
  }
}
