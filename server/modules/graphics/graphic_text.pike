constant cvs_version="$Id: graphic_text.pike,v 1.118 1998/03/23 18:55:16 grubba Exp $";
constant thread_safe=1;

#include <module.h>
#include <stat.h>
inherit "module";
inherit "roxenlib";

#ifndef VAR_MORE
#define VAR_MORE	0
#endif /* VAR_MORE */

static private int loaded;

static private string doc()
{
  return !loaded?"":replace(Stdio.read_bytes("modules/tags/doc/graphic_text")
			    ||"", ({ "{", "}" }), ({ "&lt;", "&gt;" }));
}

array register_module()
{
  return ({ MODULE_LOCATION | MODULE_PARSER,
	      "Graphics text",
	      ("Generates graphical texts.<p>"
	       "See <tt>&lt;gtext help&gt;&lt;/gtext&gt;</tt> for "
	       "more information.\n<p>"+doc()), 0, 1, });
}

void create()
{
  defvar("cache_dir", "../gtext_cache", "Cache directory for gtext images",
	 TYPE_DIR,
	 "The gtext tag saves images when they are calculated in this "
	 "directory. We currently do not clean this directory.");
  
  defvar("cache_age", 48, "Cache max age",
	 TYPE_INT,
	 "If the images in the cache have not been accessed for this "
	 "number of hours they are removed.");
  
  defvar("speedy", 0, "Avoid automatic detection of document colors",
	 TYPE_FLAG|VAR_MORE,
	 "If this flag is set, the tags 'body', 'tr', 'td', 'font' and 'th' "
	 " will <b>not</b> be parsed to automatically detect the colors of "
	 " a document. You will then have to specify all colors in all calls "
	 " to &lt;gtext&gt;");
  
  defvar("deflen", 300, "Default maximum text-length", TYPE_INT|VAR_MORE,
	 "The module will, per default, not try to render texts "
	 "longer than this. This is a safeguard for things like "
	 "&lt;gh1&gt;&lt;/gh&gt;, which would otherwise parse the"
	 " whole document. This can be overrided with maxlen=... in the "
	 "tag.");

  defvar("location", "/gtext/", "Mountpoint", TYPE_LOCATION|VAR_MORE,
	 "The URL-prefix for the graphic characters.");

  defvar("cols", 16, "Default number of colors per image", TYPE_INT_LIST,
	 "The default number of colors to use. 16 seems to be enough. "
	 "The size of the image depends on the number of colors",
	 ({ 1,2,3,4,5,6,7,8,10,16,32,64,128,256 }));

  defvar("gif", 0, "Append .gif to all images", TYPE_FLAG|VAR_MORE,
	 "Append .gif to all images made by gtext. Normally this will "
	 "only waste bandwidth");
  // compatibility variables...
  defvar("default_size", 32, 0, TYPE_INT,0,0,1);
  defvar("default_font", "urw_itc_avant_garde-demi-r",0,TYPE_STRING,0,0,1);
}

string query_location() { return query("location"); }

object load_font(string name, string justification, int xs, int ys)
{
  object fnt = Image.font();

  if ((!name)||(name == ""))
  {
    return get_font("default",32,0,0,lower_case(justification||"left"),
		    (float)xs, (float)ys);
  } else if(sscanf(name, "%*s/%*s") != 2) {
    name=QUERY(default_size)+"/"+name;
  }

  name = "fonts/" + name;

  if(!fnt->load( name ))
  {
    report_debug("Failed to load the compatibility font "+name+
		 ", using the default font.\n");
    return get_font("default",32,0,0,lower_case(justification||"left"),
		    (float)xs, (float)ys);
  }
  catch
  {
    if(justification=="right") fnt->right();
    if(justification=="center") fnt->center();
    if(xs)fnt->set_x_spacing((100.0+(float)xs)/100.0);
    if(ys)fnt->set_y_spacing((100.0+(float)ys)/100.0);
  };
  return fnt;
}

static private mapping (int:mapping(string:mixed)) cached_args = ([ ]);

string base_key;
object mc;


array to_clean = ({});
void clean_cache_dir()
{
  if(!sizeof(to_clean))
    to_clean = get_dir(query("cache_dir"));
  if(!sizeof(to_clean)) return;
  int md = file_stat(query("cache_dir")+to_clean[0])[ST_ATIME];
  
  if((time() - md) > (query("cache_age")*3600))
    rm(query("cache_dir")+to_clean[0]);
  
  to_clean = to_clean[1..];
  if(sizeof(to_clean))
    call_out(clean_cache_dir, 0.1);
  else
    call_out(clean_cache_dir, 3600);
}

void start(int|void val, object|void conf)
{
  loaded = 1;

  if(conf)
  {
    mkdirhier( query( "cache_dir" )+"/.foo" );
#ifndef __NT__
#if efun(chmod)
    // FIXME: Should this error be propagated?
    catch { chmod( query( "cache_dir" ), 0777 ); };
#endif
#endif
    remove_call_out(clean_cache_dir);
    call_out(clean_cache_dir, 10);
    mc = conf;
    base_key = "gtext:"+(conf?conf->name:roxen->current_configuration->name);
  }
}

int number=0;
mapping find_cached_args(int num);


#if !constant(iso88591)
constant iso88591
=([ "&nbsp;":   "�",  "&iexcl;":  "�",  "&cent;":   "�",  "&pound;":  "�",
    "&curren;": "�",  "&yen;":    "�",  "&brvbar;": "�",  "&sect;":   "�",
    "&uml;":    "�",  "&copy;":   "�",  "&ordf;":   "�",  "&laquo;":  "�",
    "&not;":    "�",  "&shy;":    "�",  "&reg;":    "�",  "&macr;":   "�",
    "&deg;":    "�",  "&plusmn;": "�",  "&sup2;":   "�",  "&sup3;":   "�",
    "&acute;":  "�",  "&micro;":  "�",  "&para;":   "�",  "&middot;": "�",
    "&cedil;":  "�",  "&sup1;":   "�",  "&ordm;":   "�",  "&raquo;":  "�",
    "&frac14;": "�",  "&frac12;": "�",  "&frac34;": "�",  "&iquest;": "�",
    "&Agrave;": "�",  "&Aacute;": "�",  "&Acirc;":  "�",  "&Atilde;": "�",
    "&Auml;":   "�",  "&Aring;":  "�",  "&AElig;":  "�",  "&Ccedil;": "�",
    "&Egrave;": "�",  "&Eacute;": "�",  "&Ecirc;":  "�",  "&Euml;":   "�",
    "&Igrave;": "�",  "&Iacute;": "�",  "&Icirc;":  "�",  "&Iuml;":   "�",
    "&ETH;":    "�",  "&Ntilde;": "�",  "&Ograve;": "�",  "&Oacute;": "�",
    "&Ocirc;":  "�",  "&Otilde;": "�",  "&Ouml;":   "�",  "&times;":  "�",
    "&Oslash;": "�",  "&Ugrave;": "�",  "&Uacute;": "�",  "&Ucirc;":  "�",
    "&Uuml;":   "�",  "&Yacute;": "�",  "&THORN;":  "�",  "&szlig;":  "�",
    "&agrave;": "�",  "&aacute;": "�",  "&acirc;":  "�",  "&atilde;": "�",
    "&auml;":   "�",  "&aring;":  "�",  "&aelig;":  "�",  "&ccedil;": "�",
    "&egrave;": "�",  "&eacute;": "�",  "&ecirc;":  "�",  "&euml;":   "�",
    "&igrave;": "�",  "&iacute;": "�",  "&icirc;":  "�",  "&iuml;":   "�",
    "&eth;":    "�",  "&ntilde;": "�",  "&ograve;": "�",  "&oacute;": "�",
    "&ocirc;":  "�",  "&otilde;": "�",  "&ouml;":   "�",  "&divide;": "�",
    "&oslash;": "�",  "&ugrave;": "�",  "&uacute;": "�",  "&ucirc;":  "�",
    "&uuml;":   "�",  "&yacute;": "�",  "&thorn;":  "�",  "&yuml;":   "�",
]);
#endif



constant nbsp = iso88591["&nbsp;"];
constant replace_from = indices( iso88591 )+ ({"&ss;","&lt;","&gt;","&amp",});
constant replace_to   = values( iso88591 ) + ({ nbsp, "<", ">", "&", }); 

#define simplify_text( from ) replace(from,replace_from,replace_to)

#define FNAME(a,b) (query("cache_dir")+sprintf("%x",hash(reverse(a[6..])))+sprintf("%x",hash(b))+sprintf("%x",hash(reverse(b-" ")))+sprintf("%x",hash(b[12..])))

array get_cache_file(string a, string b)
{
  object fd = open(FNAME(a,b), "r");
  if(!fd) return 0;
  array r = decode_value(fd->read());
  if(r[0]==a && r[1]==b) return r[2];
}

void store_cache_file(string a, string b, array data)
{
  object fd = open(FNAME(a,b), "wct");
#ifndef __NT__
#if efun(chmod)
  // FIXME: Should this error be propagated?
  catch { chmod( FNAME(a,b), 0666 ); };
#endif
#endif
  if(!fd) return;
  fd->write(encode_value(({a,b,data})));
  destruct(fd);
}


array(int)|string write_text(int _args, string text, int size, object id)
{
  string key = base_key+_args;
  array err;
  string orig_text = text;
  mixed data;
  mapping args = find_cached_args(_args);

  if(!args)
  {
    throw( ({ "Internal error in gtext: Got request for non-existant gtext class", backtrace() }) );
  }

  if(data = cache_lookup(key, text))
  {
    if(args->nocache) // Remove from cache. Very useful for access counters
      cache_remove(key, text);
    if(size) return data[1];
    return data[0];
  } else if(data = get_cache_file( key, text )) {
    cache_set(key, text, data);
    if(size) return data[1];
    return data[0];
  }


  // So. We have to actually draw the thing...

  object img;
  if(!args)
  {
    args=(["fg":"black","bg":"white","notrans":"1"]);
    text="Please reload this page";
  }

  if(!args->verbatim)
  {
    text = replace(text, nbsp, " ");
    text = simplify_text( text );
    string res="",nspace="",cspace="";
    foreach(text/"\n", string line)
    {
      cspace="";nspace="";
      foreach(line/" ", string word)
      {
	string nonum;
	if(strlen(word) &&
	   (nonum = replace(word,
			    ({"1","2","3","4","5","6","7","8","9","0","."}),
			    ({"","","","","","","","","","",""}))) == "") {
	  cspace=nbsp+nbsp;
	  if((strlen(word)-strlen(nonum)<strlen(word)/2) &&
	     (upper_case(word) == word)) {
	    word=((word/"")*nbsp);
	  }
	} else if(cspace!="") {
	  cspace=" ";
	}
	res+=(nspace==cspace?nspace:" ")+word;

	if(cspace!="")   nspace=cspace;
	else    	   nspace=" ";
      }
      res+="\n";
    }
    text = replace(res[..strlen(res)-2], ({ "!","?",": " }), ({ nbsp+"!",nbsp+"?",nbsp+": " }));
    text = replace(replace(replace(text,({". ",". "+nbsp}), ({"\000","\001"})),".","."+nbsp+nbsp),({"\000","\001"}),({". ","."+nbsp}));
  }

//  cache_set(key, text, "rendering");

  if(args->nfont)
  {
    int bold, italic;
    if(args->bold) bold=1;
    if(args->light) bold=-1;
    if(args->italic) italic=1;
    if(args->black) bold=2;
    data = get_font(args->nfont,(int)args->font_size||32,bold,italic,
		    lower_case(args->talign||"left"),
		    (float)(int)args->xpad, (float)(int)args->ypad);
  }
  else if(args->font)
  {
    // compatibility fonts...
    data = load_font(args->font, lower_case(args->talign||"left"),
		     (int)args->xpad,(int)args->ypad);
  } else {
    int bold, italic;
    if(args->bold) bold=1;
    if(args->light) bold=-1;
    if(args->italic) italic=1;
    if(args->black) bold=2;
    data = get_font(roxen->QUERY(default_font),32,bold,italic,
		    lower_case(args->talign||"left"),
		    (float)(int)args->xpad, (float)(int)args->ypad);
  }

  if (!data) {
    roxen_perror("gtext: No font!\n");
    return(0);
  }

  // Fonts and such are now initialized.
  // Draw the actual image....
  img = GText.make_text_image(args,data,text,dirname(id->not_query),id);
  
  // Now we have the image in 'img', or nothing.
  if(!img) return 0;
  
  //	 Quantify
  if(!args->fs)
  {
    int q=(int)args->quant||
      (args->background||args->texture?150:QUERY(cols));
    if(q>255) q=255;
    if(q<3) q=3;
    img=img->map_closest(img->select_colors(q-1)+({parse_color(args->bg)}));
  }

  if(!args->scroll)
  {
    if(args->fadein)
    {
      // Animated fade	
      int amount=2, steps=10, delay=10, initialdelay=0, ox;
      string res = img->gif_begin();
      sscanf(args->fadein, "%d,%d,%d,%d", amount, steps, delay, initialdelay);
      if(initialdelay)
      {
	object foo=Image.image(img->xsize(),img->ysize(),@parse_color(args->bg));
	res += foo->gif_add(0,0,initialdelay);
      }
      for(int i = 0; i<(steps-1); i++)
      {
	object foo=img->clone();
	foo = foo->apply_matrix(GText.make_matrix(((int)((steps-i)*amount))));
	res += foo->gif_add(0,0,delay);
      }
      res+= img->gif_add(0,0,delay);
      res += img->gif_end();
      data = ({ res, ({ img->xsize(), img->ysize() }) });
    } else {
      // NORMAL IMAGE HERE
      if(args->fs)
	data=({ img->togif_fs(@(args->notrans?({}):parse_color(args->bg))),
		({img->xsize(),img->ysize()})});
      else
	data=({ img->togif(@(args->notrans?({}):parse_color(args->bg))),
		({img->xsize(),img->ysize()})});
      img=0;
    }
  } else {
    // Animated scrolltext
    int len=100, steps=30, delay=5, ox;
    string res = img->gif_begin() + img->gif_netscape_loop();
    sscanf(args->scroll, "%d,%d,%d", len, steps, delay);
    img=img->copy(0,0,(ox=img->xsize())+len-1,img->ysize()-1);
    img->paste(img, ox, 0);
    for(int i = 0; i<steps; i++)
    {
      int xp = i*ox/steps;
      res += img->copy(xp, 0, xp+len, img->ysize(),
		       @parse_color(args->bg))->gif_add(0,0,delay);
    }
    res += img->gif_end();
    data = ({ res, ({ len, img->ysize() }) });
  }

  // place in caches, as a gif image.
  if(!args->nocache) store_cache_file( key, orig_text, data );
  cache_set(key, orig_text, data);
  if(size) return data[1];
  return data[0];
}

mapping find_file(string f, object rid); // Pike 0.5...
void restore_cached_args(); // Pike 0.5...


array stat_file(string f, object rid)
{
  if(f[-1]=='/') f = f[..strlen(f)-2];
  if(sizeof(f/"/")==1) return ({ 509,-3,time(),time(),time(),0,0 });
  int len=4711;
  catch(len= strlen(find_file(f,rid)->data));
  return ({ 33204,len,time(),time(),time(),0,0 });
}

array find_dir(string f, object rid)
{
  if(!strlen(f))
  {
    restore_cached_args();
    return Array.map(indices(cached_args), lambda(mixed m){return (string)m;});
  }
  return ({"Example"});
}

  
mapping find_file(string f, object rid)
{
  int id;
  if(rid->method != "GET") return 0;
  sscanf(f,"%d/%s", id, f);

  if( query("gif") )             //Remove .gif
    f = f[..strlen(f)-5];
    
  if (sizeof(f)) {
    object g;
    if (f[0] == '$') {	// Illegal in BASE64, for speed
      f = f[1..];
    } else if (sizeof(indices(g=Gz))) {
      catch(f = g->inflate()->inflate(MIME.decode_base64(f)));
    } else if (sizeof(f)) {
      catch(f = MIME.decode_base64(f));
    }
  }

  return http_string_answer(write_text(id,f,0,rid), "image/gif");
}

mapping url_cache = ([]);
string quote(string in)
{
  string option;
  if(option = url_cache[in]) return option;
  object g;
  if (sizeof(indices(g=Gz))) {
    option=MIME.encode_base64(g->deflate()->deflate(in));
  } else {
    option=MIME.encode_base64(in);
  }
  if(search(in,"/")!=-1) return url_cache[in]=option;
  string res="$";	// Illegal in BASE64
  for(int i=0; i<strlen(in); i++)
    switch(in[i])
    {
     case 'a'..'z':
     case 'A'..'Z':
     case '0'..'9':
     case '.': case ',': case '!':
      res += in[i..i];
      break;
     default:
      res += sprintf("%%%02x", in[i]);
    }
  if(strlen(res) < strlen(option)) return url_cache[in]=res;
  return url_cache[in]=option;
}

#define ARGHASH query("cache_dir")+"ARGS_"+hash(mc->name)

int args_restored = 0;
void restore_cached_args()
{
  args_restored = 1;
  object o = open(ARGHASH, "r");
  if(o)
  {
    string data = o->read();
    catch {
      object q;
      if(sizeof(indices(q=Gz)))
	data=q->inflate()->inflate(data);
    };
    catch {
      cached_args |= decode_value(data);
    };
  }
  if (cached_args && sizeof(cached_args)) {
    number = sort(indices(cached_args))[-1]+1;
  } else {
    cached_args = ([]);
    number = 0;
  }
}

void save_cached_args()
{
  int on;
  on = number;
  restore_cached_args();
  if(on > number) number=on;
  object o = open(ARGHASH, "wct");
#ifndef __NT__
#if efun(chmod)
  // FIXME: Should this error be propagated?
  catch { chmod( ARGHASH, 0666 ); };
#endif
#endif
  string data=encode_value(cached_args);
  catch {
    object q;
    if(sizeof(indices(q=Gz)))
      data=q->deflate()->deflate(data);
  };
  o->write(data);
}

mapping find_cached_args(int num)
{
  if(!args_restored) restore_cached_args();
  if(cached_args[num]) return cached_args[num];
  restore_cached_args();
  if(cached_args[num]) return cached_args[num];
  return 0;
}



int find_or_insert(mapping find)
{
  mapping f2 = copy_value(find);
  foreach(glob("magic_*", indices(f2)), string q) m_delete(f2,q);
  if(!args_restored)   restore_cached_args();
  array a = indices(cached_args);
  array b = values(cached_args);
  int i;

  for(i=0; i<sizeof(a); i++) if(equal(f2, b[i])) return a[i];
  restore_cached_args();
  for(i=0; i<sizeof(a); i++) if(equal(f2, b[i])) return a[i];
  cached_args[number]=find;
  remove_call_out(save_cached_args);
  call_out(save_cached_args, 10);
  return number++;
}


string magic_javascript_header(object id)
{
  if(!id->supports->netscape_javascript || !id->supports->images) return "";
  return
    ("\n<script>\n"
     "function i(ri,hi,txt)\n"
     "{\n"
     "  document.images[ri].src = hi.src;\n"
     "  setTimeout(\"top.window.status = '\"+txt+\"'\", 100);\n"
     "}\n"
     "</script>\n");

}


string magic_image(string url, int xs, int ys, string sn,
		   string image_1, string image_2, string alt,
		   string mess,object id,string input,string extra_args)
{
  if(!id->supports->images) return alt;
  if(!id->supports->netscape_javascript)
    return (!input)?
      ("<a "+extra_args+"href=\""+url+"\"><img src=\""+image_1+"\" name="+sn+" border=0 "+
       "alt=\""+alt+"\"></a>\n"):
    ("<input type=image "+extra_args+" src=\""+image_1+"\" name="+input+">");

  return
    ("<script>\n"
     " "+sn+"l = new Image("+xs+", "+ys+");"+sn+"l.src = \""+image_1+"\";\n"
     " "+sn+"h = new Image("+xs+", "+ys+");"+sn+"h.src = \""+image_2+"\";\n"
     "</script>\n"+
     ("<a "+extra_args+"href=\""+url+"\" "+
      (input?"onClick='document.forms[0].submit();' ":"")
      +"onMouseover=\"i('"+sn+"',"+sn+"h,'"+(mess||url)+"'); return true;\"\n"
      "onMouseout='top.window.status=\"\";document.images[\""+sn+"\"].src = "+sn+"l.src;'><img "
      "width="+xs+" height="+ys+" src=\""+image_1+"\" name="+sn+
      " border=0 alt=\""+alt+"\" ></a>\n"));
}


string extra_args(mapping in)
{
  string s="";
  foreach(indices(in), string i)
  {
    switch(i)
    {
     case "target":
     case "hspace":
     case "vspace":
     case "onclick":
      s+=i+"='"+in[i]+"' ";
      m_delete(in, i);
      break;
    }
  }
  return s;
}

string tag_gtext_id(string t, mapping arg,
		    object id, object foo, mapping defines)
{
  int short=!!arg->short;
  if(arg->help) return "Arguments are identical to the argumets to &lt;gtext&gt;. This tag returns a url-prefix that can be used to generate gtexts.";
  m_delete(arg, "short"); m_delete(arg, "maxlen");
  m_delete(arg,"magic");  m_delete(arg,"submit");
  extra_args(arg);        m_delete(arg,"split");
  if(defines->fg && !arg->fg) arg->fg=defines->fg;
  if(defines->bg && !arg->bg) arg->bg=defines->bg;
#if efun(get_font)
  if(!arg->nfont) arg->nfont=defines->nfont;
#endif
  if(!arg->font) arg->font=defines->font
#if !efun(get_font)
		   ||QUERY(default_font)
#endif
		   ;

  int num = find_or_insert( arg );

  if(!short)
    return query_location()+num+"/";
  else
    return (string)num;
}



string tag_graphicstext(string t, mapping arg, string contents,
			object id, object foo, mapping defines)
{
//Allow <accessed> and others inside <gtext>.
  
  if(t=="gtext" && arg->help)
    return doc();
  else if(arg->help)
    return "This tag calls &lt;gtext&gt; with different default values.";
  if(arg->background) 
    arg->background = fix_relative(arg->background,id);
  if(arg->texture) 
    arg->texture = fix_relative(arg->texture,id);
  if(arg->magic_texture)
    arg->magic_texture=fix_relative(arg->magic_texture,id);
  if(arg->magic_background) 
    arg->magic_background=fix_relative(arg->magic_background,id);
  if(arg->magicbg) 
    arg->magicbg = fix_relative(arg->magicbg,id);

  string gif="";
  if(query("gif")) gif=".gif";
  
#if efun(_static_modules)
  contents = parse_rxml(contents, id, foo, defines);
#else
  contents = parse_rxml(contents, id, foo);
#endif

  string lp, url, ea;
  string pre, post, defalign, gt, rest, magic;
  int i;
  string split;

  // No images here, let's generate an alternative..
  if(!id->supports->images || id->prestate->noimages)
  {
    if(!arg->split) contents=replace(contents,"\n", "\n<br>\n");
    if(arg->submit) return "<input type=submit name=\""+(arg->name+".x")
		      + "\" value=\""+contents+"\">";
    switch(t)
    {
     case "gtext":
     case "anfang":
      if(arg->href)
	return "<a href=\""+arg->href+"\">"+contents+"</a>";
      return contents;
     default:
      if(sscanf(t, "%s%d", t, i)==2)
	rest="<h"+i+">"+contents+"</h"+i+">";
      else
	rest="<h1>"+contents+"</h1>";
      if(arg->href)
	return "<a href=\""+arg->href+"\">"+rest+"</a>";
      return rest;
      
    }
  }

  contents = contents[..((int)arg->maxlen||QUERY(deflen))];
  m_delete(arg, "maxlen");

  if(arg->magic)
  {
    magic=replace(arg->magic,"'","`");
    m_delete(arg,"magic");
  }

  int input;
  if(arg->submit)
  {
    input=1;
    m_delete(arg,"submit");
  }
  

  ea = extra_args(arg);

  // Modify the 'arg' mapping...
  if(arg->href)
  {
    url = arg->href;
    lp = "<a href=\""+arg->href+"\" "+ea+">";
    if(!arg->fg) arg->fg=defines->link||"#0000ff";
    m_delete(arg, "href");
  }

  if(defines->fg && !arg->fg) arg->fg=defines->fg;
  if(defines->bg && !arg->bg) arg->bg=defines->bg;
  if(!arg->nfont) arg->nfont=defines->nfont;
  if(!arg->font) arg->font=defines->font;
  if(!arg->bold) arg->bold=defines->bold;
  if(!arg->italic) arg->italic=defines->italic;
  if(!arg->black) arg->black=defines->black;
  if(!arg->narrow) arg->narrow=defines->narrow;

  if(arg->split)
  {
    if (sizeof(split=arg->split) != 1)
      split = " ";
    m_delete(arg,"split");
  }

  // Support for <gh 2> like things.
  for(i=2; i<10; i++) 
    if(arg[(string)i])
    {
      arg->scale = 1.0 / ((float)i*0.6);
      m_delete(arg, (string)i);
      break;
    }

  // Support for <gh1> like things.
  if(sscanf(t, "%s%d", t, i)==2)
    if(i > 1) arg->scale = 1.0 / ((float)i*0.6);

  string na = arg->name, al=arg->align;
  m_delete(arg, "name"); m_delete(arg, "align");

  // Now the 'args' mapping is modified enough..
  int num = find_or_insert( arg );

  gt=contents;
  rest="";

  switch(t)
  {
   case "gh1": case "gh2": case "gh3": case "gh4":
   case "gh5": case "gh6": case "gh7":
   case "gh": pre="<p>"; post="<br>"; defalign="top"; break;
   case "gtext":
    pre="";  post=""; defalign="bottom";
    break;
   case "anfang":
    gt=contents[0..0]; rest=contents[1..];
    pre="<br clear=left>"; post=""; defalign="left";
    break;
  }

  if(split)
  {
    string word;
    array res = ({ pre });
    string pre = query_location() + num + "/";

    if(lp) res+=({ lp });
    
    gt=replace(gt, "\n", " ");
    
    foreach(gt/" "-({""}), word)
    {
      if (split != " ") {
	array arr = word/split;
	int i;
	for (i = sizeof(arr)-1; i--;)
	  arr[i] += split;
	if (arr[-1] == "")
	  arr = arr[..sizeof(arr)-2];
	foreach (arr, word) {
	  array size = write_text(num,word,1,id);
	  res += ({ "<img border=0 alt=\"" +
		      replace(arg->alt || word, "\"", "'") +
		      "\" src=\"" + pre + quote(word) + gif + "\" width=" +
		      size[0] + " height=" + size[1] + " " + ea + ">"
		      });
	}
	res += ({"\n"});
      } else {
	array size = write_text(num,word,1,id);
	res += ({ "<img border=0 alt=\"" +
		    replace(arg->alt || word, "\"", "'") +
		    "\" src=\"" + pre + quote(word) + gif + "\" width=" +
		    size[0] + " height=" + size[1] + " " + ea + ">\n"
		    });
      }
    }
    if(lp) res += ({ "</a>"+post });
    return res*"";
  }
  
  array size = write_text(num,gt,1,id);
  if(!size)
    return ("<font size=+1><b>Missing font or other similar error -- "
	    "failed to render text</b></font>");

  if(magic)
  {
    string res = "";
    if(!arg->fg) arg->fg=defines->link||"#0000ff";
    arg = mkmapping(indices(arg), values(arg));
    if(arg->fuzz)
      if(arg->fuzz != "fuzz")
	arg->glow = arg->fuzz;
      else
	arg->glow = arg->fg;
    arg->fg = defines->alink||"#ff0000";
    if(arg->magicbg) arg->background = arg->magicbg;
    if(arg->bevel) arg->pressed=1;

    foreach(glob("magic_*", indices(arg)), string q)
    {
      arg[q[6..]]=arg[q];
      m_delete(arg, q);
    }
    
    int num2 = find_or_insert(arg);
    array size = write_text(num2,gt,1,id);

    if(!defines->magic_java) res = magic_javascript_header(id);
    defines->magic_java="yes";

    return replace(res +
		   magic_image(url||"", size[0], size[1], "i"+(defines->mi++),
			       query_location()+num+"/"+quote(gt)+gif,
			       query_location()+num2+"/"+quote(gt)+gif,
			       (arg->alt?arg->alt:replace(gt, "\"","'")),
			       (magic=="magic"?0:magic),
			       id,input?na||"submit":0,ea),
		   "</script>\n<script>","");
  }
  if(input)
    return (pre+"<input type=image name=\""+na+"\" border=0 alt=\""+
	    (arg->alt?arg->alt:replace(gt,"\"","'"))+
	    "\" src="+query_location()+num+"/"+quote(gt)+gif
	    +" align="+(al || defalign)+ea+
	    " width="+size[0]+" height="+size[1]+">"+rest+post);

  return (pre+(lp?lp:"")
	  + "<img border=0 alt=\""
	  + (arg->alt?arg->alt:replace(gt,"\"","'"))
	  + "\" src=\""
	  + query_location()+num+"/"+quote(gt)+gif+"\" "+ea
	  + " align="+(al || defalign)
	  + " width="+size[0]+" height="+size[1]+">"+rest+(lp?"</a>":"")+post);
}

inline string ns_color(array (int) col)
{
  if(!arrayp(col)||sizeof(col)!=3)
    return "#000000";
  return sprintf("#%02x%02x%02x", col[0],col[1],col[2]);
}


string make_args(mapping in)
{
  array a=indices(in), b=values(in);
  for(int i=0; i<sizeof(a); i++)
    if(lower_case(b[i])!=a[i])
      if(search(b,"\"")==-1)
	a[i]+="=\""+b[i]+"\"";
      else
	a[i]+="='"+b[i]+"'";
  return a*" ";
}

string|array (string) tag_body(string t, mapping args, object id, object file,
			       mapping defines)
{
  int cols,changed;
  if(args->help) return "This tag is parsed by &lt;gtext&gt; to get the document colors.";
  if(args->bgcolor||args->text||args->link||args->alink
     ||args->background||args->vlink)
    cols=1;

#define FIX(Y,Z,X) do{if(!args->Y || args->Y==""){if(cols){defines->X=Z;args->Y=Z;changed=1;}}else{defines->X=args->Y;if(args->Y[0]!='#'){args->Y=ns_color(parse_color(args->Y));changed=1;}}}while(0)

  if(!search((id->client||({}))*"","Mosaic"))
  {
    FIX(bgcolor,"#bfbfbf",bg);
    FIX(text,   "#000000",fg);
    FIX(link,   "#0000b0",link);
    FIX(alink,  "#3f0f7b",alink);
    FIX(vlink,  "#ff0000",vlink);
  } else {
    FIX(bgcolor,"#c0c0c0",bg);
    FIX(text,   "#000000",fg);
    FIX(link,   "#0000ee",link);
    FIX(alink,  "#ff0000",alink);
    FIX(vlink,  "#551a8b",vlink);
  }
  if(changed) return ({make_tag("body", args) });
}


string|array(string) tag_fix_color(string tagname, mapping args, object id, 
				   object file, mapping defines)
{
  int changed;

  if(args->help) return "This tag is parsed by &lt;gtext&gt; to get the document colors.";
  if(!id->misc->colors)
    id->misc->colors = ({ ({ defines->fg, defines->bg, tagname }) });
  else
    id->misc->colors += ({ ({ defines->fg, defines->bg, tagname }) });
#undef FIX
#define FIX(X,Y) if(args->X && args->X!=""){defines->Y=args->X;if(args->X[0]!='#'){args->X=ns_color(parse_color(args->X));changed = 1;}}

  FIX(bgcolor,bg);
  FIX(text,fg);
  FIX(color,fg);
  if(changed) return ({"<"+tagname+" "+make_args(args)+">"});
  return 0;
}

string|void pop_color(string tagname,mapping args,object id,object file,
		 mapping defines)
{
  array c = id->misc->colors;
  if(args->help) return "This end-tag is parsed by &lt;gtext&gt; to get the document colors.";
  if(!c ||!sizeof(c)) return;
  int i;
  tagname = tagname[1..];

  for(i=0;i<sizeof(c);i++)
    if(c[-i-1][2]==tagname)
    {
      defines->fg = c[-i-1][0];
      defines->bg = c[-i-1][1];
      break;
    }

  c = c[..-i-2];
  id->misc->colors = c;
}

mapping query_tag_callers()
{
  return ([ "gtext-id":tag_gtext_id, ]) | (query("speedy")?([]):
  (["font":tag_fix_color,
    "body":tag_body,
    "table":tag_fix_color,
    "tr":tag_fix_color,
    "td":tag_fix_color,
    "layer":tag_fix_color,
    "ilayer":tag_fix_color,
    "/td":pop_color,
    "/tr":pop_color,
    "/font":pop_color,
    "/body":pop_color,
    "/table":pop_color,
    "/layer":pop_color,
    "/ilayer":pop_color,
   ]));
}


mapping query_container_callers()
{
  return ([ "anfang":tag_graphicstext,
	    "gh":tag_graphicstext,
	    "gh1":tag_graphicstext, "gh2":tag_graphicstext,
	    "gh3":tag_graphicstext, "gh4":tag_graphicstext,
	    "gh5":tag_graphicstext, "gh6":tag_graphicstext,
	    "gtext":tag_graphicstext, ]);
}
