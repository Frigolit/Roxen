/* parse_line.pike
 *
 */

class partial_literal
{
  int length;

  void create(int l) { length = l; }
}

string buffer;

void create(string line)
{
  buffer = line;
}

void skip_whitespace()
{
  sscanf(buffer, "%*[ \t]%s", buffer);
}

// Returns -1 on error. All valid numbers ar non-negative.
int get_number()
{
  skip_whitespace();
      
  if (!strlen(buffer))
    return -1;

  int i;
  for(i = 0; i<strlen(buffer); i++)
    if ( (buffer[i] < '0') || ('9' < buffer[i]) )
      break;
      
  // Disallow too large numbers
  if (!i || (i > 9) )
    return -1;
      
  int res = array_sscanf(buffer[..i-1], "%d")[0];
  buffer = buffer[i..];
  return res;
}

string get_atom(int|void with_options)
{
  string atom;

  werror("get_atom: buffer = '%s'\n", buffer);
      
  sscanf(buffer,
	 (with_options
	  ? "%*[ \t]%[^][(){ \0-\037\177%*\"\\]%s"
	  : "%*[ \t]%[^(){ \0-\037\177%*\"\\]%s"),
	 atom, buffer);
      
  if (strlen(buffer))
    switch(buffer[0])
    {
    case ' ':
    case '\t':
      break;
    case '[':
      if (with_options)
	break;
      /* Fall through */
    default:
      return 0;
    }
      
  return strlen(atom) && atom;
}

string|object get_string()
{
  werror("get_string: buffer = '%s'\n", buffer);

  skip_whitespace();

  if (!strlen(buffer))
    return 0;
      
  switch(buffer[0])
  {
  case '"':
  {
    int i = 0;
    while(1)
    {
      i = search(buffer, "\"", i+1);
      if (i<0)
	return 0;
      if (buffer[i-1] != '\\')
      {
	string res = replace(buffer[1..i-1],
			     ({ "\\\"", "\\\\" }),
			     ({ "\"", "\\" }) );
	buffer = buffer[i+1..];
	return res;
      }
    }
  }
  case '{':
  {
    if (buffer[strlen(buffer)-1..] != "}")
      return 0;
    string n = buffer[1..strlen(buffer)-2];

    buffer = "";
    if ( (sizeof(values(n) - values("0123456789")))
	 || (sizeof(n) > 9) )
      return 0;
    if (!sizeof(n))
      return 0;

    return partial_literal(array_sscanf(n, "%d")[0]);
  }
  }
}

string|object get_astring()
{
  werror("get_astring: buffer = '%s'\n", buffer);
      
  skip_whitespace();
  if (!strlen(buffer))
    return 0;
  switch(buffer[0])
  {
  case '"':
  case '{':
    return get_string();
  default:
    return get_atom();
  }
}
  
/* Returns a set object. */
object get_set()
{
  string atom = get_atom();
  if (!atom)
    return 0;
      
  return .types.imap_set()->init(atom);
}

/* Parses an object that (recursivly) can contain atoms (possible
   * with options in brackets) or lists. Note that strings are not
   * accepted, as it is a little difficult to wait for the
   * continuation of the request.
   *
   * FXME: This function is used to read fetch commands. This breaks
   * rfc-2060 compliance, as the names of headers can be represented
   * as string literals.
   */
  
mapping get_simple_list(int max_depth)
{
  skip_whitespace();
  if (!strlen(buffer))
    return 0;

  if (buffer[0] == '(')
  {
    /* Recurse */
    if (max_depth > 0)
    {
      array a = do_parse_simple_list(max_depth - 1, ')');
      return a && ([ "type": "list",
		     "list": a ]);
    }
    else
      return 0;
  }
  return get_atom_options(max_depth);
}

array do_parse_simple_list(int max_depth, int terminator)
{
  array a = ({ });
      
  while(1)
  {
    buffer = buffer[1..];
    skip_whitespace();
	
    if (!strlen(buffer))
      return 0;
	
    if (buffer[0] == terminator)
    {
      buffer = buffer[1..];
      return a;
    }
    mapping o = get_simple_list(max_depth);
    if (!o)
      return 0;
  }
}

/* Reads an atom, optionally followd by a list enclosed in square
   * brackets. Naturally, the atom itself cannot contain any brackets.
   *
   * Returns a mapping
   *    type : "type",
   *    atom : name,
   *    raw : name[options]
   *    options : parsed options,
   *    range : ({ start, size })
   */
mapping get_atom_options(int max_depth)
{
  string atom = get_atom(1);
  if (!atom)
    return 0;

  mapping res = ([ "type" : "atom",
		   "atom" : atom ]);
  if (!strlen(buffer) || (buffer[0] != '['))
  {
    res->raw = atom;
    return res;
  }
      
  /* Parse options */
  string option_start = buffer;
      
  array options = do_parse_simple_list(max_depth - 1, ']');
  if (!options)
    return 0;

  res->options = options;
  res->raw = option_start[..sizeof(option_start) - sizeof(buffer) - 1];
      
  if (!strlen(buffer) || (buffer[0] != '<'))
    return res;

  /* Parse <start.size> suffix */
  buffer = buffer[1..];

  int start = get_number();
  if ((start < 0) || !strlen(buffer) || (buffer[0] != '.'))
    return 0;

  buffer = buffer[1..];
      
  int size = get_number();
  if ((size < 0) || !strlen(buffer) || (buffer[0] != '>'))
    return 0;
      
  buffer = buffer[1..];

  res->range = ({ start, size });

  return res;
}
  
#if 0
/* Parsing general list requires some variation of continuation
   * passing style.
   *
   * If the entire list can be read immediately, it is returned. On
   * errors, 0 is returned. If only part of the list can be read, a
   * read handler is returned, and the passed callback function will
   * be called when the list is complete, or an error is detected.
   *
   * Could perhaps besimplified a little by *always* using the
   * callback function, using a call_out if the list can be read
   * immediately. */

array get_list(function(array:mixed))
{
}
#endif
