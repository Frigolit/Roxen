#include <module.h>
inherit "module";
inherit "roxenlib";

roxen.ImageCache the_cache;

array register_module()
{
   return 
   ({ 
      MODULE_PARSER,
      "Image converter",
      "Provides a tag 'cimg'. Usage: "
      "<cimg src=indata format=outformat [quant=numcolors] [img args]>",
      0,1
   });
}

void start()
{
  the_cache = roxen.ImageCache( "cimg", generate_image );
}

mapping generate_image( mapping args, RequestID id )
{
  return roxen.low_load_image( args->src, id );
// if( i->img && args->gamma )
//   i->img = i->img->gamma( (float)args->gamma );
}

mapping find_internal( string f, RequestID id )
{
  return the_cache->http_file_answer( f, id );
}

string tag_cimg( string t, mapping args, RequestID id )
{
  mapping a = 
  ([  
    "src":fix_relative( args->src, id ),
    "quant":args->quant,
    "format":args->format,
    "maxwidth":args->maxwidth,
    "maxheight":args->maxheight,
    "scale":args->scale,
    "dither":args->dither,
    "gamma":args->gamma,
  ]);

  foreach( glob( "*-*", indices(args)), string n )
    a[n] = args[n];

  args -= a;

  args->src = query_internal_location()+the_cache->store( a );

  if( mapping size = the_cache->metadata( a, id, 1 ) ) 
  {
    // image in cache (1 above prevents generation on-the-fly)
    args->width = size->xsize;
    args->height = size->ysize;
  }
  return make_tag( "img", args );
}

string tag_cimg_url( string t, mapping args, RequestID id )
{
  mapping a = 
  ([  
    "src":fix_relative( args->src, id ),  "quant":args->quant,
    "format":args->format, "maxwidth":args->maxwidth,
    "maxheight":args->maxheight, "scale":args->scale,
    "dither":args->dither, "gamma":args->gamma,
  ]);

  foreach( glob( "*-*", indices(args)), string n )
    a[n] = args[n];

  return query_internal_location()+the_cache->store( a );
}
