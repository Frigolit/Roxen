// This is a roxen module. Copyright � 2000, Roxen IS.

inherit "module";

constant cvs_version = "$Id: r�varspr�kare.pike,v 1.1 2000/11/18 07:34:06 nilsson Exp $";
constant thread_safe = 1;
constant module_type = MODULE_FILTER;
constant module_name = "R�varspr�kare";
constant module_doc  = "Spr�kar r�vare";

constant konsonanter = (multiset)("QWRTPSDFGHJKLZXCVBNM"/1);

int(0..1) versalp(string char) {
  return upper_case(char)==char;
}

array(string) r�vare(Parser.HTML p, string in) {

  int i;
  string ut="";
  do {
    if(!konsonanter[upper_case(in[i..i])]) {
      ut += in[i..i];
      i++;
      continue;
    }
    if(in[i]=='c' && i<sizeof(in)-1 && in[i+1]=='k') {
      ut += "kock";
      i += 2;
      continue;
    }
    if(konsonanter[in[i..i]]) {
      if((i>sizeof(in)-1 || versalp(in[i+1..i+1])) &&
	 (i==0 || versalp(ut[sizeof(ut)..sizeof(ut)])))
	ut += in[i..i] + "O" + in[i..i];
      else
	ut += in[i..i] + "o" + lower_case(in[i..i]);
    }
    else
      ut += in[i..i] + "o" + in[i..i];
    i++;
  } while(i<sizeof(in));

  return ({ ut });
}

mapping filter(mapping resultat, RequestID id) {
  if(!resultat ||
     (!id->prestate->r�vare &&
      !has_value(id->request_headers["accept-language"], "r�vare"))
     || !stringp(resultat->data) || id->misc->ber�vad)
    return 0;

  id->misc->ber�vad=1;

  resultat->data = Parser.HTML()->
    _set_data_callback(r�vare)->
    finish(resultat->data)->read();
  return resultat;
}
