// This is a small sample module.  It is intended to show a simple example
// of a container.

// This variable is shown in the configinterface as the version of the module.
string cvs_version = "$Id: fnord.pike,v 1.7 2000/02/12 15:52:04 nilsson Exp $";

// Tell Roxen that this module is threadsafe. That is there is no
// request specific data in global variables.
int thread_safe=1;

// Include and inherit code that is needed in every module.
#include <module.h>
inherit "module";


// Documentation:

// The purpose of this module is to allow comments in the SPML source
// that are invisible to average viewers, but can be seen with the
// right magic incantation.  Fnord!  The special text is rendered in
// the "sample" font, if available, which makes it possible for
// someone looking at the mixed output to distinguish text that is for
// public consumption from that which is restricted.

// See also <COMMENT> which is similar, but always removes the
// enclosed text.

// If you have a section of text (with markup, if desired) that you
// may be planning on adding later, but don't want to generally
// activate (the pointers may not have all been done, yet) you can use
// this.  It has other uses, too.

// This is not a secure way to hide text, I would like to see a
// version that requires authentication to turn on the "hidden" text,
// but this simple version does not do that.

// To use this in your SPML, enter the "hidden" text between a <FNORD>
// and </FNORD>, you can include any additional markup you desire.
// You may want to have a <P> or two to set it off, or use
// <BLOCKQUOTE> inside.  Here's a simple example:

//      The text that everyone sees. <FNORD>With some they
//      don't.</FNORD> And then some they do.

// Since the excised text may be part of a sentence flow, its removal
// may disrupt the readability.  In this case an ALT attribute can be
// used on the FNORD to give text for the mundanes to see.  This text
// should not have markup (some kinds might work, but others might
// not).  Here's an example of how that might be used:

//      This server <FNORD ALT="provides">will provide, when we
//      actually get to it,</FNORD> complete source for the ...

// The way the normally hidden text is made visible is by including
// "fnord" in the prestates (i.e. add "/(fnord)" before the "filename"
// part of the URL).

// Michael A. Patton <map@bbn.com>


// This is the code for the actual container.  By naming it "container_"
// it is automatically recognized by Roxen as the code for a container
// tag and is registered in its list of container tags.

// First, check the 'request_id->prestate' multiset for the presence
// of 'fnord'. If it is there, show the contents, otherwise, if there
// is an 'alt' text, display it, if not, simply return an empty string

string container_fnord(string tag_name, mapping arguments, string contents,
		       RequestID id )
{
  if (id->prestate->fnord)
    return contents;
  if (arguments->alt)
    return arguments->alt;
  return "";
}


// Some constants that are needed to register the module in the RXML parser.

constant module_type = MODULE_PARSER;
constant module_name = "Fnord!";
constant module_doc  = "Adds an extra container tag, &lt;fnord&gt; that's supposed to make "
  "things invisible unless the \"fnord\" prestate is present."
  "<p>This module is here as an example of how to write a "
  "very simple RXML-parsing module.</p>";


// Last, but not least, we want a documentation that can be integrated in the
// online manual. The mapping tagdoc maps from container names to it's description.

TAGDOCUMENTATION;
#ifdef manual
constant tagdoc=(["fnord":#"<desc cont>The fnord container tag hides its "
  "contents for the user, unless the fnord prestate is used.</desc>"
  "<attr name=alt value=string>An alternate text that should be written "
  "in place of the hidden text.</attr>"]);
#endif
