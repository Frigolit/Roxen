// The Atlas module. Copyright � 1999 - 2001, Roxen IS.
//
// Please note: The map is incomplete and incorrect in details.  Countries
// and territories are missing.

#include <module.h>
inherit "module";

constant cvs_version = "$Id: atlas.pike,v 1.10 2001/09/21 15:58:09 jhs Exp $";
constant thread_safe = 1;
constant module_type = MODULE_TAG | MODULE_EXPERIMENTAL;
constant module_name = "Graphics: Atlas";
constant module_doc  = 
#"Provides the <tt>&lt;atlas&gt;</tt> tag that creates a world map. It is
possible to highlight countries on the generated world map.";

roxen.ImageCache the_cache;

void start() {
  the_cache = roxen.ImageCache( "atlas", generate_image );
}

string status() {
  array s=the_cache->status();
  return sprintf("<b>Images in cache:</b> %d images<br />\n<b>Cache size:</b> %s",
		 s[0]/2, Roxen.sizetostring(s[1]));
}

mapping(string:function) query_action_buttons() {
  return ([ "Clear cache":flush_cache ]);
}

void flush_cache() {
  the_cache->flush();
}

mapping find_internal( string f, RequestID id ) {
  return the_cache->http_file_answer( f, id );
}


// ---------------------- Tags ------------------------------

class TagEmitAtlas {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "atlas";

  array get_dataset( mapping args, RequestID id ) {
    if (args->list=="countries")
      return map(Map.Earth()->countries(),
		 lambda(string c) { return (["name":c]); });
    if (args->list=="regions")
      return map(Map.Earth()->regions(),
		 lambda(string c) { return (["name":c]); });
    RXML.parse_error("No valid list argument given\n");
  }
}

constant imgargs = ({ "region", "fgcolor", "bgcolor" });

class TagAtlas {
  inherit RXML.Tag;
  constant name = "atlas";

  class TagCountry {
    inherit RXML.Tag;
    constant name = "country";
    constant flags = RXML.FLAG_EMPTY_ELEMENT;

    class Frame {
      inherit RXML.Frame;

      array do_enter(RequestID id) {
	string name;

	if(args->domain)
	  name = Map.domain_to_country[lower_case(args->domain)];
	else if(args->name)
	  name = Map.aliases[lower_case(args->name)] || args->name;

	if(!name)
	  parse_error("No domain or name attribute given.\n");

	id->misc->atlas_state->color[lower_case(name)] =
	  parse_color(args->color || "#e0c080");
	return 0;
      }
    }
  }

  class TagMarker {
    inherit RXML.Tag;
    constant name = "marker";
    constant flags = RXML.FLAG_EMPTY_ELEMENT;

    class Frame {
      inherit RXML.Frame;

      array do_enter(RequestID id) {
	if(args->x[-1]=='%')
	  args->x = (float)args->x/100.0 * args->width;
	args->x = (int)args->x;
	if(args->y[-1]=='%')
	  args->y = (float)args->y/100.0 * args->height;
	args->y = (int)args->y;

	if(args->x<0 || args->y<0 ||
	   args->x>=id->misc->atlas_state->width ||
	   args->y>=id->misc->atlas_state->height)
	  return 0;

	args->size = (int)args->size || 4;
	if(args->color)
	  args->color = parse_color(args->color);
	else
	  args->color = ({ 255, 0, 0 });

	id->misc->atlas_state->markers += ({ args });
	return 0;
      }
    }
  }

  // This tag set can probably be shared, but I don't know for sure. /mast
  RXML.TagSet internal = RXML.TagSet(this_module(), "atlas",
				     ({ TagCountry(),
					TagMarker() }) );

  class Frame {
    inherit RXML.Frame;
    RXML.TagSet additional_tags = internal;

    array do_enter(RequestID id) {
      // Construct a state which will be used
      // in order to draw the image later on.
      mapping state = ([ "color":([]),
			 "markers":({}) ]);

      // Calculate size of image.  Preserve
      // image aspect ratio if possible.
      int w, h;
      if(args->width) {
	sscanf(args->width, "%d", w);
	h = (int)(w*3.0/5.0);
	sscanf(args->height||"", "%d", h);
      } else {
	sscanf(args->height||"300", "%d", h);
	w = (int)(h*5.0/3.0);
      }
      state->width = w;
      state->height = h;

      args->width = (string)w;
      args->height = (string)h;

      foreach( imgargs, string arg)
	if(args[arg])
	  state[arg]=m_delete(args, arg);

      id->misc->atlas_state = state;
    }

    array do_return(RequestID id) {
      mapping state = id->misc->atlas_state;

      args->src = query_absolute_internal_location(id) +
	the_cache->store(state, id);
      if(!args->alt)
	args->alt = state->region || "The World";

      result = RXML.t_xml->format_tag("img", args);
      return 0;
    }
  }
}

Image generate_image(mapping state, RequestID id)
{
  if(!state)
    return 0;

  state->fgcolor = parse_color(state->fgcolor || "#ffffff");

  mapping opt = ([ "color_fu":
		   lambda(string name) {
		     return state->color[name] || state->fgcolor;
		   } ]);


  if(state->bgcolor)
    opt->color_sea = parse_color(state->bgcolor);

  if(state->markers)
    opt->markers = state->markers;

  Map.Earth m = Map.Earth( state->region );

  Image img = m->image(state->width, state->height, opt);

  return img;
}

TAGDOCUMENTATION;
#ifdef manual
constant tagdoc=([
"emit#atlas": ({ #"<desc type='plugin'><p><short>
 Lists regions and countries defined in the atlas tag map.</short></p>
</desc>

<attr name='list' value='regions|countries'><p>
 Select what type of objects to list.</p>

<ex>
<b>Available regions</b><br />
<emit source='atlas' list='regions'>
&_.name;<br />
</emit>
</ex>
</attr>",

([
  "&_.name;":#"<desc type='entity'><p>
   The name of the region/country</p>
  </desc>"
])

  }),
"atlas":({ #"<desc type='cont'><p><short>

 Draws a map.</short> The map shows either the world, regions (Africa, Europe,
 etc) or countries. It's a known bug that the map is not entierly up to date.</p>

<ex><atlas/></ex>

<ex><atlas fgcolor='#425A84' bgcolor='#dee2eb'>
<country domain='se' color='orange'/>
<country domain='jp' color='orange'/>
<marker x='100' y='90'/>
</atlas>
</ex>
</desc>

<attr name='region' value='name' default='The World'><p>
 Which map to show. The value may be any of the listed region values
 that emit plugin <xref href='../output/emit_atlas.tag'>atlas</xref>
 returns.</p>

<ex><atlas region='europe' width='200'/></ex>
</attr>

<attr name='width' value='number'><p>
 The width of the image.</p>
</attr>

<attr name='height' value='number'><p>
 The height of the image.</p>
</attr>

<attr name='fgcolor' value='color' default='white'><p>
 The color of the unselected land areas.</p>
</attr>

<attr name='bgcolor' value='color' default='#101040'><p>
 The color of the sea areas.</p>
</attr>",

([
"country" : #"<desc tag='tag'><p><short>
 A region that should be highlighted with a different color on the map.</short></p>
</desc>

<attr name='domain' value='name'><p>
 The top domain of the country that should be highlighted.</p>
</attr>

<attr name='name' value='name'><p>
 The name of the country that should be highlighted. A list of available
 names can be aquired from the <xref href='../output/emit_atlas.tag'>atlas</xref>
 emit plugin.</p></attr>

<attr name='color' value='color' default='#e0c080'><p>
 The color that should be used for highlighting.</p>
</attr>",

"marker" : #"<desc tag='tag'><p><short>
 Draws a marker at the specified position</short></p>
</desc>

<attr name='x' value='pixels or percentage' required='required'><p>
  The distance from the left of the map.</p>
</attr>

<attr name='y' value='pixels or percentage' required='required'><p>
  The distance from the top of the map.</p>
</attr>

<attr name='color' value='color' default='red'><p>
  The color of the marker</p>
</attr>

<attr name='style' value='box|diamond' default='diamond'><p>
  The type of marker.</p>

<ex><atlas region='europe' width='150'>
<marker x='100' y='30' style='diamond' />
<marker x='125' y='30' style='box' />
</atlas>
</ex>
</attr>

<attr name='size' value='number' default='4'><p>
  The size of the marker.</p>
</attr>"
	       ])
  }),
]);
#endif
