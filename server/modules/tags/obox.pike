// The outlined box module, Copyright � 1996 - 2000, Roxen IS.
//
// Fredrik Noring et al
//
// Several modifications by Francesco Chemolli.


constant cvs_version = "$Id: obox.pike,v 1.31 2000/11/02 12:54:17 kuntri Exp $";
constant thread_safe=1;

#include <module.h>
inherit "module";

TAGDOCUMENTATION
#ifdef manual
constant tagdoc=(["obox":([
  "standard":#"<desc cont='cont'><p<<short>
 This tag creates an outlined box.</short>
</p></desc>

<attr name=align value=left|right>
 Vertical alignment of the box.
</attr>

<attr name=bgcolor value=color>
 Color of the background and title label.
</attr>

<attr name=fixedleft value=number>
 Fixed length of line on the left side of the title. The unit is the
 approximate width of a character.
</attr>

<attr name=fixedright value=number>
 Fixed length of line on the right side of the title. The unit is the
 approximate width of a character.
</attr>

<attr name=left value=number>
 Length of the line on the left of the title.
</attr>

<attr name=outlinecolor value=color>
 Color of the outline.
</attr>

<attr name=outlinewidth value=number>
 Width, in pixels, of the outline.
</attr>

<attr name=right value=number>
 Length of the line on the right of the title.
</attr>

<attr name=spacing value=number>
 Width, in pixels, of the space in the box.
</attr>

<attr name=style value=caption|groupbox>
 Style of the box. Groupbox is default
</attr>

<attr name=textcolor value=color>
 Color of the text inside the box.
</attr>

<attr name=title value=string>
 Sets the title of the obox.
</attr>

<attr name=titlecolor value=color>
 Color of the title text.
</attr>

<attr name=width value=number>
 Width, in pixels, of the box.


 Note that the left and right attributes are constrained by the width
 argument. If the title is not specified in the argument list, you can
 put it in a <tag>title</tag> container in the obox contents.

<ex><obox align='left' outlinewidth='5' outlinecolor='green' width='200'>
<title>Sample box</title>

This is just a sample box.

</obox>
</ex>

</attr>",


  "svenska":#"<desc cont='cont><p><short>
 Denna tagg skapar en raml�da runt dess inneh�ll.</short>
</p></desc>

<attr name=align value=left|right>
 Raml�dans vertikala position.
</attr>

<attr name=bgcolor value=f�rg>
 F�rgen p� bakgrunden samt titeln.
</attr>

<attr name=fixedleft value=nummer>
 L�ngden p� linjen till v�nster om titeln. V�rdet p� 1 'nummer' �r den
 ungef�rliga bredden av ett tecken.
</attr>

<attr name=fixedright value=nummer>
 L�ngden p� linjen till v�nster om titeln. V�rdet p� 1 'nummer' �r den
 ungef�rliga bredden av ett tecken.
</attr>

<attr name=left value=nummer>
 L�ngden p� linjen till v�nster om titeln.
</attr>

<attr name=outlinecolor value=f�rg>
 F�rgen p� ramen.
</attr>

<attr name=outlinewidth value=nummer>
 Ramens bredd, i antal pixlar.
</attr>

<attr name=right value=nummer>
 L�ngden p� linjen till h�ger om titeln.
</attr>

<attr name=spacing value=nummer>
 Vidden p� utrymmet i raml�dan, i antal pixlar.
</attr>

<attr name=style value=caption|groupbox>
 Raml�dans stil. Groupbox �r standardv�rde.
</attr>

<attr name=textcolor value=f�rg>
 F�rgen p� texten inuti l�dan.
</attr>

<attr name=title value=textstr�ng>
 Raml�dans titel.
</attr>

<attr name=titlecolor value=f�rg>
 F�rgen p� titeltexten.
 </attr>

<attr name=width value=nummer>
 Bredden p� l�dan, i antal pixlar.

 T�nk p� att <att>left</att> och <att>right</att> attributen begr�nsas
 av v�rdet p� <att>width</att> attributet. Om titeln inte �r satt i
 taggen, finns m�jligheten att s�tta den inuti en <tag>title</tag>
 tagg och placera denna i raml�dans inneh�ll.

<ex><obox align='left' outlinewidth='5' outlinecolor='green' width='200'>
<title>Raml�da</title>

Detta �r inneh�llet.

</obox>
</ex>

</attr>"]) ]);
#endif

constant unit_gif = "/internal-roxen-unit";

static string img_placeholder (mapping args)
{
  int width=((int)args->outlinewidth)||1;

  return sprintf("<img src=\"%s\" alt=\"\" width=\"%d\" height=\"%d\"%s>",
		 unit_gif, width, width, (args->noxml?"":" /"));
}

static string handle_title(string name, mapping junk_args,
			   string contents, mapping args)
{
  args->title=contents;
  return "";
}

static string horiz_line(mapping args)
{
  args->fixedleft="";
  return sprintf("<tr><td colspan=\"5\" bgcolor=\"%s\">\n"
		 "%s</td></tr>\n",
		 args->outlinecolor,
		 img_placeholder(args));
}

static string title(mapping args)
{
  if (!args->title)
    return horiz_line(args);
  string empty=img_placeholder(args);
  if (!args->left && !args->fixedleft)
    if (args->width && !args->fixedright)
      args->fixedleft = "7";
    else
      args->left = "20";
  if (!args->right && !args->fixedright)
    args->right = args->width || "20";
  switch (args->style) {
   case "groupbox":
    return sprintf("<tr><td colspan=\"2\"><font size=\"-3\">&nbsp;</font></td>\n"
		   "<td rowspan=\"3\"%s nowrap=\"nowrap\">&nbsp;<b>"		/* bgcolor */
		   "%s%s%s"                 /* titlecolor, title, titlecolor */
		   "</b>&nbsp;</td>\n"
		   "<td colspan=\"2\"><font size=\"-3\">&nbsp;</font></td></tr>\n"
		   "<tr%s>"				/* bgcolor */
		   "<td bgcolor=\"%s\" colspan=\"2\">\n"	/* outlinecolor */
		   "%s</td>\n"				/* empty */
		   "<td bgcolor=\"%s\" colspan=\"2\">\n"
		   "%s</td></tr>\n"			/* empty */

		   "<tr%s><td bgcolor=\"%s\">"      /* bgcolor, outlinecolor */
		   "%s</td>\n"				/* empty */
		   "<td%s><font size=\"-3\">%s</font></td>" /* left, fixedleft */
		   "<td%s><font size=\"-3\">%s</font></td>\n" /* right, fixedright */
		   "<td bgcolor=\"%s\">"		/* outlinecolor */
		   "%s</td></tr>\n"			/* empty */
		   ,
		   args->bgcolor ? " bgcolor=\""+args->bgcolor+"\"" : "",
		   args->titlecolor ? "<font color=\""+args->titlecolor+"\">" : "",
		   args->title,
		   args->titlecolor ? "</font>" : "",
		   args->bgcolor ? " bgcolor=\""+args->bgcolor+"\"" : "",
		   args->outlinecolor,
		   empty,
		   args->outlinecolor,
		   empty,
		   args->bgcolor ? " bgcolor=\""+args->bgcolor+"\"" : "",
		   args->outlinecolor,
		   empty,
		   args->left ? " width=\""+args->left+"\"" : "",
		   (args->fixedleft ?
		    String.strmult ("&nbsp;", (int) args->fixedleft) : "&nbsp;"),
		   args->right ? " width=\""+args->right+"\"" : "",
		   (args->fixedright ?
		    String.strmult ("&nbsp;", (int) args->fixedright) : "&nbsp;"),
		   args->outlinecolor,
		   empty);
   case "caption":
    return sprintf("<tr%s><td colspan=\"2\"><font size=\"-3\">&nbsp;</font></td>\n"
		   "<td rowspan=\"3\" nowrap=\"nowrap\">&nbsp;<b>"		/* bgcolor */
		   "%s%s%s"                 /* titlecolor, title, titlecolor */
		   "</b>&nbsp;</td>\n"
		   "<td colspan=\"2\"><font size=\"-3\">&nbsp;</font></td></tr>\n"
		   "<tr bgcolor=\"%s\">"		/* outlinecolor */
		   "<td colspan=\"2\">\n"	
		   "%s</td>\n"				/* empty */
		   "<td colspan=\"2\">\n"
		   "%s</td></tr>\n"			/* empty */

		   "<tr bgcolor=\"%s\"><td>"      /*  outlinecolor */
		   "%s</td>\n"				/* empty */
		   "<td%s><font size=\"-3\">%s</font></td>" /* left, fixedleft */
		   "<td%s><font size=\"-3\">%s</font></td>\n" /* right, fixedright */
		   "<td bgcolor=\"%s\">"		/* outlinecolor */
		   "%s</td></tr>\n"			/* empty */
		   ,
		   args->outlinecolor ? " bgcolor=\""+args->outlinecolor+"\"" : "",
		   args->titlecolor ? "<font color=\""+args->titlecolor+"\">" : "",
		   args->title,
		   args->titlecolor ? "</font>" : "",
		   args->outlinecolor,
		   empty,
		   empty,
		   args->outlinecolor,
		   empty,
		   args->left ? " width=\""+args->left+"\"" : "",
		   (args->fixedleft ?
		    String.strmult ("&nbsp;", (int) args->fixedleft) : "&nbsp;"),
		   args->right ? " width=\""+args->right+"\"" : "",
		   (args->fixedright ?
		    String.strmult ("&nbsp;", (int) args->fixedright) : "&nbsp;"),
		   args->outlinecolor,
		   empty);
  }
}

string simpletag_obox(string name, mapping args, string contents)
{
  string s;

  // Set the defaults...
  args->outlinecolor = args->outlinecolor || "#000000";
  args->style = args->style || "groupbox";
  if (!args->title) {
    contents=parse_html(contents,([]),(["title":handle_title,]),args);
  }

  s = "<table border=\"0\" cellpadding=\"0\" cellspacing=\"0\"" +
    (args->align?" align=\""+args->align+"\"":"") +
    (args->width ? " width=" + args->width : "") +
    (args->hspace ? " hspace=" + args->hspace : "") +
    (args->vspace ? " vspace=" + args->vspace : "") +  ">\n" +
    title(args) +
    "<tr" +
    (args->bgcolor?" bgcolor=\""+args->bgcolor+"\"":"") +
    "><td bgcolor=\"" + args->outlinecolor + "\">" +
    img_placeholder(args) + "</td>\n"
    "<td" + (args->width && !args->fixedleft && !args->fixedright ? " width=\"1\"" : "") +
    (args->aligncontents ? " align=" + args->aligncontents : "") + " colspan=\"3\"" + ">\n"
    "<table border=\"0\" cellspacing=\"0\" cellpadding=\"" + (args->padding || "5") + "\""+
    (!args->spacing && args->width?" width=\""+(string)((int)args->width-((int)args->outlinewidth*2||2))+"\"":"")+
    (args->spacing?" width=\""+(string)args->spacing+"\"":"")+">"
    "<tr><td>\n";

    if (args->textcolor)
      s += "<font color=\""+args->textcolor+"\">" + contents + "</font>";
    else
      s += contents;

    s += "</td></tr></table>\n"
      "</td><td bgcolor=\"" + args->outlinecolor + "\">" +
      img_placeholder(args) + "</td></tr>\n" +
      horiz_line(args) + "</table>\n";

  return s;
}

constant module_type = MODULE_TAG;
constant module_name =
    ([
      "standard":"Outlined box",
      "svenska":"Raml�da",
    ]);
constant module_doc =
    ([
      "standard":
      "This module provides the <tt>&lt;obox&gt;</tt> tag that draws outlined "
      "boxes.",
      "svenska":
      "<tt>&lt;obox&gt;&lt;/obox&gt;</tt> �r en tag som ramar "
      "in det som st�r i den.",
    ]);
