/*
 * name = "Abstract language class";
 * doc = "Handles the conversion of numbers and dates. You have to restart the server for updates to take effect.";
 */

// Array(string) with the months of the year, beginning with January
constant months = ({ "", "", "", "", "", "", "", "", "", "", "", "" });

// Array(string) with the days of the week, beginning with Sunday
constant days = ({ "", "", "", "", "", "", "" });

// The ISO 639 language codes
constant ISO639=([
  "aa":"Afar",
  "ab":"Abkhazian",
  "af":"Afrikaans",
  "am":"Amharic",
  "ar":"Arabic",
  "as":"Assamese",
  "ay":"Aymara",
  "az":"Azerbaijani",

  "ba":"Bashkir",
  "be":"Byelorussian",
  "bg":"Bulgarian",
  "bh":"Bihari",
  "bi":"Bislama",
  "bn":"Bengali", //Bangla
  "bo":"Tibetan",
  "br":"Breton",

  "ca":"Catalan",
  "co":"Corsican",
  "cs":"Czech",
  "cy":"Welsh",

  "da":"Danish",
  "de":"German",
  "dz":"Bhutani",

  "el":"Greek",
  "en":"English",
  "eo":"Esperanto",
  "es":"Spanish",
  "et":"Estonian",
  "eu":"Basque",

  "fa":"Persian",
  "fi":"Finnish",
  "fj":"Fiji",
  "fo":"Faeroese",
  "fr":"French",
  "fy":"Frisian",

  "ga":"Irish",
  "gd":"Scots", //Gaelic
  "gl":"Galician",
  "gn":"Guarani",
  "gu":"Gujarati",

  "ha":"Hausa",
  "hi":"Hindi",
  "hr":"Croatian",
  "hu":"Hungarian",
  "hy":"Armenian",

  "ia":"Interlingua",
  "ie":"Interlingue",
  "ik":"Inupiak",
  "in":"Indonesian",
  "is":"Icelandic",
  "it":"Italian",
  "iw":"Hebrew",

  "ja":"Japanese",
  "ji":"Yiddish",
  "jw":"Javanese",

  "ka":"Georgian",
  "kk":"Kazakh",
  "kl":"Greenlandic",
  "km":"Cambodian",
  "kn":"Kannada",
  "ko":"Korean",
  "ks":"Kashmiri",
  "ku":"Kurdish",
  "ky":"Kirghiz",

  "la":"Latin",
  "ln":"Lingala",
  "lo":"Laothian",
  "lt":"Lithuanian",
  "lv":"Latvian", //Lettish

  "mg":"Malagasy",
  "mi":"Maori",
  "mk":"Macedonian",
  "ml":"Malayalam",
  "mn":"Mongolian",
  "mo":"Moldavian",
  "mr":"Marathi",
  "ms":"Malay",
  "mt":"Maltese",
  "my":"Burmese",

  "na":"Nauru",
  "ne":"Nepali",
  "nl":"Dutch",
  "no":"Norwegian",

  "oc":"Occitan",
  "om":"Oromo", //(Afan)
  "or":"Oriya",

  "pa":"Punjabi",
  "pl":"Polish",
  "ps":"Pashto", //Pushto
  "pt":"Portuguese",

  "qu":"Quechua",

  "rm":"Rhaeto-Romance",
  "rn":"Kirundi",
  "ro":"Romanian",
  "ru":"Russian",
  "rw":"Kinyarwanda",

  "sa":"Sanskrit",
  "sd":"Sindhi",
  "sg":"Sangro",
  "sh":"Serbo-Croatian",
  "si":"Singhalese",
  "sk":"Slovak",
  "sl":"Slovenian",
  "sm":"Samoan",
  "sn":"Shona",
  "so":"Somali",
  "sq":"Albanian",
  "sr":"Serbian",
  "ss":"Siswati",
  "st":"Sesotho",
  "su":"Sundanese",
  "sv":"Swedish",
  "sw":"Swahili",

  "ta":"Tamil",
  "te":"Telugu",
  "tg":"Tajik",
  "th":"Thai",
  "ti":"Tigrinya",
  "tk":"Turkmen",
  "tl":"Tagalog",
  "tn":"Setswana",
  "to":"Tonga",
  "tr":"Turkish",
  "ts":"Tsonga",
  "tt":"Tatar",
  "tw":"Twi",

  "uk":"Ukrainian",
  "ur":"Urdu",
  "uz":"Uzbek",

  "vi":"Vietnamese",
  "vo":"Volapuk",

  "wo":"Wolof",

  "xh":"Xhosa",

  "yo":"Yoruba",

  "zh":"Chinese",
  "zu":"Zulu"
]);

// Mapping(string:string) from language code to language name
constant languages = ISO639;

// Array(string) with all the language's identifiers
constant _aliases = ({});

// Array(string) with language code, the language in english
// and the native language description.
constant _id = ({ "??", "Unknown", "Unknown" });

array id()
{
  return _id;
}

string month(int num)
{
  return months[ num - 1 ];
}

string day(int num)
{
  return days[ num - 1 ];
}

array aliases()
{
  return _aliases;
}

string language(string code)
{
  return languages[code];
}

mapping list_languages()
{
  return languages;
}

string number(int i)
{
  return (string)i;
}

string ordered(int i)
{
  return (string)i;
}

string date(int i, mapping|void m)
{
  mapping lt=localtime(i);
  return sprintf("%4d-%02d-%02d", lt->year+1900, lt->mon+1, lt->mday);
}
